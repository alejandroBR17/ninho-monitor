import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'camera.dart';
import 'rtsp_probe.dart';

/// RTSP text and binary interleaved RTP/RTCP must never be parsed as one stream.
class RtspFramer {
  final List<int> _buffer = [];
  List<Uint8List> add(List<int> bytes) {
    _buffer.addAll(bytes);
    if (_buffer.length > 2 * 1024 * 1024) {
      throw const FormatException('Mensagem RTSP excedeu 2 MB.');
    }
    final frames = <Uint8List>[];
    while (_buffer.isNotEmpty) {
      int length;
      if (_buffer.first == 36) {
        if (_buffer.length < 4) break;
        length = 4 + (_buffer[2] << 8) + _buffer[3];
      } else {
        final end = RtspReply.headerEnd(_buffer);
        if (end == null) {
          if (_buffer.length > 65536) {
            throw const FormatException('Cabeçalho RTSP excedeu 64 KB.');
          }
          break;
        }
        final header = latin1.decode(_buffer.sublist(0, end));
        final match = RegExp(
          r'^Content-Length:\s*(\d+)',
          multiLine: true,
          caseSensitive: false,
        ).firstMatch(header);
        length = end + 4 + (match == null ? 0 : int.parse(match[1]!));
        if (length > 1024 * 1024) {
          throw const FormatException('Corpo RTSP excedeu 1 MB.');
        }
      }
      if (_buffer.length < length) break;
      frames.add(Uint8List.fromList(_buffer.sublist(0, length)));
      _buffer.removeRange(0, length);
    }
    return frames;
  }
}

class RtspMessage {
  String line;
  final Map<String, String> headers;
  Uint8List body;
  final Map<String, String> headerNames;
  RtspMessage(this.line, this.headers, this.body, [Map<String, String>? names])
    : headerNames = names ?? {};
  factory RtspMessage.parse(List<int> bytes) {
    final end = RtspReply.headerEnd(bytes);
    if (end == null) throw const FormatException('Mensagem RTSP incompleta.');
    final lines = latin1.decode(bytes.sublist(0, end)).split('\r\n');
    final headers = <String, String>{};
    final names = <String, String>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).toLowerCase();
      names[key] = line.substring(0, colon);
      final value = line.substring(colon + 1).trim();
      headers[key] = headers.containsKey(key)
          ? '${headers[key]}, $value'
          : value;
    }
    return RtspMessage(
      lines.first,
      headers,
      Uint8List.fromList(bytes.sublist(end + 4)),
      names,
    );
  }
  static const _canonicalNames = {
    'cseq': 'CSeq',
    'content-length': 'Content-Length',
    'content-type': 'Content-Type',
    'authorization': 'Authorization',
    'session': 'Session',
    'transport': 'Transport',
  };
  Uint8List encode() {
    if (body.isNotEmpty || headers.containsKey('content-length')) {
      headers['content-length'] = '${body.length}';
    }
    final header =
        '$line\r\n${headers.entries.map((e) => '${headerNames[e.key] ?? _canonicalNames[e.key] ?? e.key}: ${e.value}\r\n').join()}\r\n';
    return Uint8List.fromList([...latin1.encode(header), ...body]);
  }
}

String normalizeTcpTransport(String requested, String received) {
  final expected = RegExp(
    r'(?:^|;)\s*interleaved=(\d+-\d+)',
    caseSensitive: false,
  ).firstMatch(requested)?[1];
  final actual = RegExp(
    r'(?:^|;)\s*interleaved=(\d+-\d+)',
    caseSensitive: false,
  ).firstMatch(received)?[1];
  if (!requested.toUpperCase().startsWith('RTP/AVP/TCP;') ||
      expected == null ||
      expected != actual) {
    return received;
  }
  // Only repair the observed missing /TCP. Never relabel an explicit UDP reply,
  // multicast, or a reply with UDP ports or mismatching interleaved channels.
  if (!RegExp(r'^RTP/AVP;', caseSensitive: false).hasMatch(received) ||
      RegExp(
        r'(?:server_port|client_port|multicast)',
        caseSensitive: false,
      ).hasMatch(received)) {
    return received;
  }
  return received.replaceFirst(
    RegExp(r'^RTP/AVP', caseSensitive: false),
    'RTP/AVP/TCP',
  );
}

String rewriteDigestAuthorization(
  String authorization,
  String method,
  String target,
  CameraConfig config,
) {
  if (!authorization.toLowerCase().startsWith('digest ')) return authorization;
  final values = parseChallenge(authorization.substring(7));
  final algorithm = (values['algorithm'] ?? 'MD5').toUpperCase();
  if (!['MD5', 'MD5-SESS', 'SHA-256', 'SHA-256-SESS'].contains(algorithm) ||
      values['realm'] == null ||
      values['nonce'] == null) {
    throw const FormatException('Digest não suportado na compatibilidade TCP.');
  }
  final qop = values['qop'];
  if (qop != null && qop != 'auth') {
    throw const FormatException(
      'Digest qop não suportado na compatibilidade TCP.',
    );
  }
  String hash(String input) => (algorithm.startsWith('SHA-256') ? sha256 : md5)
      .convert(utf8.encode(input))
      .toString();
  var ha1 = hash('${config.username}:${values['realm']}:${config.password}');
  if (algorithm.endsWith('-SESS')) {
    ha1 = hash('$ha1:${values['nonce']}:${values['cnonce']}');
  }
  final ha2 = hash('$method:$target');
  final digest = qop == null
      ? hash('$ha1:${values['nonce']}:$ha2')
      : hash(
          '$ha1:${values['nonce']}:${values['nc']}:${values['cnonce']}:auth:$ha2',
        );
  String quote(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  values['username'] = config.username;
  values['uri'] = target;
  values['response'] = digest;
  return 'Digest ${values.entries.map((e) => ['algorithm', 'qop', 'nc'].contains(e.key) ? '${e.key}=${e.value}' : '${e.key}="${quote(e.value)}"').join(', ')}';
}

/// Entirely on the phone: binds only to loopback and relays one camera.
/// Only RTSP headers/URI routing are adapted. RTP/RTCP bytes stay unchanged.
class RtspCompatibilityBridge {
  RtspCompatibilityBridge({required this.config, required this.onStatus});
  final CameraConfig config;
  final void Function(Map<String, dynamic>) onStatus;
  final String _token = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  ServerSocket? _server;
  Socket? _client, _upstream;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Map<String, String> _transports = {};
  final Map<String, dynamic> _status = {
    'escopo': 'loopback_no_celular',
    'correcoesTransporte': <Map<String, String>>[],
    'respostas': <Map<String, dynamic>>[],
    'pacotesIntercalados': 0,
    'bytesIntercalados': 0,
  };
  bool _closed = false;
  String? _session, _lastAuthorization;
  int _lastCseq = 0;
  String _remoteHost = '';
  Uri get uri => config.uri.replace(
    host: '127.0.0.1',
    port: _server!.port,
    path: '/$_token${config.uri.path}',
  );
  void _emit() {
    if (!_closed) onStatus(Map<String, dynamic>.from(_status));
  }

  Future<void> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed) {
      await server.close();
      return;
    }
    _server = server;
    _subscriptions.add(
      server.listen((client) {
        if (_closed || _client != null) {
          client.destroy();
          return;
        }
        _client = client;
        unawaited(
          client.done.then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              if (!_closed && identical(_client, client)) _fail(error);
            },
          ),
        );
        final framer = RtspFramer();
        late StreamSubscription<Uint8List> reading;
        reading = client.listen(
          (data) {
            reading.pause();
            unawaited(
              _fromClient(data, framer).whenComplete(() {
                if (!_closed) reading.resume();
              }),
            );
          },
          onDone: () {
            if (identical(_client, client)) unawaited(_release());
          },
          onError: (Object error) {
            _fail(error);
          },
        );
        _subscriptions.add(reading);
      }),
    );
    _status['ativa'] = true;
    _emit();
  }

  Future<void> _fromClient(List<int> bytes, RtspFramer framer) async {
    try {
      for (final frame in framer.add(bytes)) {
        if (_closed) return;
        if (frame.first == 36) {
          _upstream?.add(frame);
          continue;
        }
        final message = RtspMessage.parse(frame);
        final request = message.line.split(' ');
        if (request.length != 3) {
          throw const FormatException('Linha de requisição RTSP inválida.');
        }
        final local = Uri.tryParse(request[1]);
        if (local == null ||
            local.host != '127.0.0.1' ||
            local.port != _server!.port ||
            !local.path.startsWith('/$_token/')) {
          throw const FormatException('Destino local RTSP inválido.');
        }
        final remote = local.replace(
          host: config.host,
          port: config.port,
          userInfo: '',
          path: local.path.substring(_token.length + 1),
        );
        final method = request.first;
        message.line = '$method $remote ${request[2]}';
        if (message.headers['authorization'] != null) {
          message.headers['authorization'] = rewriteDigestAuthorization(
            message.headers['authorization']!,
            method,
            remote.toString(),
            config,
          );
          _lastAuthorization = message.headers['authorization'];
        }
        final seq = message.headers['cseq'] ?? '';
        _lastCseq = int.tryParse(seq) ?? _lastCseq;
        if (method == 'SETUP') {
          _transports[seq] = message.headers['transport'] ?? '';
        }
        if (_upstream == null) {
          final socket = await Socket.connect(
            config.host,
            config.port,
            timeout: const Duration(seconds: 3),
          );
          if (_closed) {
            socket.destroy();
            return;
          }
          _upstream = socket;
          unawaited(
            socket.done.then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) {
                if (!_closed && identical(_upstream, socket)) _fail(error);
              },
            ),
          );
          _remoteHost = socket.remoteAddress.address;
          _status['enderecoAlvo'] = socket.address.address;
          _status['enderecoRemoto'] = socket.remoteAddress.address;
          final incoming = RtspFramer();
          _subscriptions.add(
            socket.listen(
              (data) {
                try {
                  for (final packet in incoming.add(data)) {
                    _fromCamera(packet);
                  }
                } catch (error) {
                  _fail(error);
                }
              },
              onDone: () {
                if (!identical(_upstream, socket)) return;
                _status['conexaoCameraEncerrada'] = true;
                _emit();
                _client?.destroy();
                _client = null;
                _upstream = null;
              },
              onError: (Object error) {
                _fail(error);
              },
            ),
          );
        }
        _upstream!.add(message.encode());
      }
    } catch (error) {
      _fail(error);
    }
  }

  String _toLocal(String value) => value.replaceAllMapped(
    RegExp(r'''rtsp://[^\s<>"',;]+''', caseSensitive: false),
    (match) {
      final remote = Uri.tryParse(match[0]!);
      if (remote == null || ![config.host, _remoteHost].contains(remote.host)) {
        return match[0]!;
      }
      return remote
          .replace(
            host: '127.0.0.1',
            port: _server!.port,
            userInfo: '',
            path: '/$_token${remote.path}',
          )
          .toString();
    },
  );
  void _fromCamera(Uint8List packet) {
    if (_closed) return;
    if (packet.first == 36) {
      _status['pacotesIntercalados'] =
          (_status['pacotesIntercalados'] as int) + 1;
      _status['bytesIntercalados'] =
          (_status['bytesIntercalados'] as int) + packet.length - 4;
      if (_status['pacotesIntercalados'] == 1) {
        _status['primeiroCanal'] = packet[1];
        _emit();
      }
      _client?.add(packet);
      return;
    }
    final message = RtspMessage.parse(packet);
    final seq = message.headers['cseq'] ?? '';
    final transport = message.headers['transport'];
    if (transport != null) {
      final corrected = normalizeTcpTransport(
        _transports[seq] ?? '',
        transport,
      );
      if (corrected != transport) {
        (_status['correcoesTransporte'] as List).add({
          'recebido': transport,
          'entregueAoMotor': corrected,
          'motivo': '/TCP ausente com canais intercalados correspondentes',
        });
        message.headers['transport'] = corrected;
      }
    }
    if (message.headers['session'] != null) {
      _session = message.headers['session']!.split(';').first;
    }
    final responses = _status['respostas'] as List;
    if (responses.length < 40) {
      responses.add({
        'status': message.line,
        'cseq': seq,
        'transporteCamera': ?transport,
        if (message.headers['transport'] != null)
          'transporteMotor': message.headers['transport'],
      });
    }
    for (final key in [
      'content-base',
      'content-location',
      'location',
      'rtp-info',
    ]) {
      if (message.headers[key] != null) {
        message.headers[key] = _toLocal(message.headers[key]!);
      }
    }
    if (message.headers['content-type']?.toLowerCase().contains(
          'application/sdp',
        ) ==
        true) {
      message.body = Uint8List.fromList(
        utf8.encode(_toLocal(utf8.decode(message.body, allowMalformed: true))),
      );
    }
    _client?.add(message.encode());
    _emit();
  }

  void _fail(Object error) {
    if (_closed) return;
    _status['erro'] = {
      'tipo': error.runtimeType.toString(),
      'mensagem': error.toString(),
    };
    _emit();
    unawaited(_release());
  }

  Future<void> _release() async {
    final socket = _upstream;
    _upstream = null;
    _client?.destroy();
    _client = null;
    if (socket != null) {
      try {
        if (_session != null) {
          final target = config.uri.replace(userInfo: '').toString();
          final auth = _lastAuthorization == null
              ? null
              : rewriteDigestAuthorization(
                  _lastAuthorization!,
                  'TEARDOWN',
                  target,
                  config,
                );
          socket.add(
            utf8.encode(
              'TEARDOWN $target RTSP/1.0\r\nCSeq: ${++_lastCseq}\r\nSession: $_session\r\n${auth == null ? '' : 'Authorization: $auth\r\n'}\r\n',
            ),
          );
          await socket.flush().timeout(const Duration(milliseconds: 200));
        }
      } catch (_) {
        /* Socket may already have been closed by the camera. */
      }
      socket.destroy();
    }
    _session = null;
    _lastAuthorization = null;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server?.close();
    await _release();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }
}
