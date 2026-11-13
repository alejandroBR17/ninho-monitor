import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'camera.dart';

class RtspReply {
  final int status;
  final Map<String, String> headers;
  final String body;
  RtspReply(this.status, this.headers, this.body);
  static int? headerEnd(List<int> bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return null;
  }

  static RtspReply parse(List<int> bytes) {
    final end = headerEnd(bytes);
    if (end == null) throw const FormatException('Cabeçalho RTSP incompleto.');
    final lines = latin1.decode(bytes.sublist(0, end)).split('\r\n');
    final match = RegExp(
      r'^RTSP/1\.[01] (\d{3})(?:\s|$)',
    ).firstMatch(lines.first);
    if (match == null) {
      throw const FormatException(
        'A porta respondeu sem uma linha de status RTSP válida.',
      );
    }
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon > 0) {
        final key = line.substring(0, colon).trim().toLowerCase();
        final value = line.substring(colon + 1).trim();
        headers[key] = headers.containsKey(key)
            ? '${headers[key]}, $value'
            : value;
      }
    }
    return RtspReply(
      int.parse(match[1]!),
      headers,
      utf8.decode(bytes.sublist(end + 4), allowMalformed: true),
    );
  }
}

Map<String, String> parseChallenge(String challenge) {
  final result = <String, String>{};
  for (final match in RegExp(
    r'(\w+)\s*=\s*(?:"([^"]*)"|([^,\s]+))',
  ).allMatches(challenge)) {
    result[match[1]!.toLowerCase()] = match[2] ?? match[3]!;
  }
  return result;
}

String? rtspAuthorization(
  String challenge,
  CameraConfig config,
  String uri, {
  String? cnonce,
  String method = 'DESCRIBE',
}) {
  final digestIndex = challenge.toLowerCase().indexOf('digest ');
  if (digestIndex < 0) {
    if (challenge.toLowerCase().contains('basic ')) {
      return 'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}';
    }
    return null;
  }
  final fields = parseChallenge(challenge.substring(digestIndex + 7));
  if (!fields.containsKey('realm') || !fields.containsKey('nonce')) return null;
  final algorithm = (fields['algorithm'] ?? 'MD5').toUpperCase();
  if (!['MD5', 'MD5-SESS', 'SHA-256', 'SHA-256-SESS'].contains(algorithm)) {
    return null;
  }
  String hash(String input) => (algorithm.startsWith('SHA-256') ? sha256 : md5)
      .convert(utf8.encode(input))
      .toString();
  final random = Random.secure();
  final clientNonce =
      cnonce ??
      List.generate(
        12,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
  var ha1 = hash('${config.username}:${fields['realm']}:${config.password}');
  if (algorithm.endsWith('-SESS')) {
    ha1 = hash('$ha1:${fields['nonce']}:$clientNonce');
  }
  final ha2 = hash('$method:$uri');
  final qops = fields['qop']
      ?.split(',')
      .map((e) => e.trim().toLowerCase())
      .toList();
  if (qops != null && !qops.contains('auth')) return null;
  final qop = qops == null ? null : 'auth';
  final response = qop == null
      ? hash('$ha1:${fields['nonce']}:$ha2')
      : hash('$ha1:${fields['nonce']}:00000001:$clientNonce:auth:$ha2');
  String quote(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  final values = [
    'username="${quote(config.username)}"',
    'realm="${quote(fields['realm']!)}"',
    'nonce="${quote(fields['nonce']!)}"',
    'uri="${quote(uri)}"',
    'response="$response"',
    'algorithm=$algorithm',
    if (qop != null) ...[
      'qop=auth',
      'nc=00000001',
      'cnonce="$clientNonce"',
    ] else if (algorithm.endsWith('-SESS'))
      'cnonce="$clientNonce"',
    if (fields['opaque'] != null) 'opaque="${quote(fields['opaque']!)}"',
  ];
  return 'Digest ${values.join(', ')}';
}

/// Bounded, read-only control-channel probe. Does not SETUP/PLAY or receive RTP.
class RtspProbe {
  Socket? _socket;
  StreamSubscription<List<int>>? _subscription;
  Completer<void>? _changed;
  final List<int> _bytes = [];
  bool _closed = false, _cancelled = false;
  Object? _socketError;
  int _cseq = 0;
  late DateTime _deadline;
  final Map<String, dynamic> result = {
    'tipo': 'controle_rtsp_tcp_sem_RTP',
    'respostas': <Map<String, dynamic>>[],
  };
  void cancel() {
    _cancelled = true;
    _socket?.destroy();
    _wake();
  }

  void _wake() {
    final pending = _changed;
    _changed = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  Duration _remaining() {
    if (_cancelled) throw StateError('Teste RTSP cancelado.');
    final ms = _deadline.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) throw TimeoutException('Prazo total do teste RTSP esgotado.');
    return Duration(milliseconds: min(ms, 2000));
  }

  Future<void> _connect(CameraConfig config) async {
    await _subscription?.cancel();
    _socket?.destroy();
    _bytes.clear();
    _closed = false;
    _socketError = null;
    _cseq = 0;
    result['etapa'] = 'conexao_tcp';
    final watch = Stopwatch()..start();
    _socket = await Socket.connect(
      config.host,
      config.port,
      timeout: _remaining(),
    );
    if (_cancelled) {
      _socket?.destroy();
      throw StateError('Teste RTSP cancelado.');
    }
    result['tcpConectado'] = true;
    result['enderecoAlvo'] = _socket!.address.address;
    result['enderecoRemoto'] = _socket!.remoteAddress.address;
    result['conexaoMs'] = watch.elapsedMilliseconds;
    _subscription = _socket!.listen(
      (data) {
        if (_bytes.length + data.length > 300000) {
          _socketError = const FormatException(
            'Resposta RTSP ultrapassou o limite de 300 KB.',
          );
          _socket?.destroy();
          _closed = true;
        } else {
          _bytes.addAll(data);
        }
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
      onError: (Object e) {
        _socketError = e;
        _closed = true;
        _wake();
      },
    );
  }

  Future<RtspReply> _request(
    CameraConfig config,
    String method, {
    String? authorization,
  }) async {
    if (_closed || _socket == null) await _connect(config);
    result['etapa'] = method;
    final sequence = ++_cseq;
    final uri = config.uri.replace(userInfo: '').toString();
    final request =
        '$method $uri RTSP/1.0\r\nCSeq: $sequence\r\nUser-Agent: JortanViewer/1.1.0\r\n'
        '${method == 'DESCRIBE' ? 'Accept: application/sdp\r\n' : ''}'
        '${authorization == null ? '' : 'Authorization: $authorization\r\n'}\r\n';
    final watch = Stopwatch()..start();
    _socket!.add(utf8.encode(request));
    await _socket!.flush().timeout(_remaining());
    while (true) {
      _remaining();
      if (_socketError != null) throw _socketError!;
      final end = RtspReply.headerEnd(_bytes);
      if (end != null) {
        if (end > 32768) {
          throw const FormatException('Cabeçalho RTSP ultrapassou 32 KB.');
        }
        final header = latin1.decode(_bytes.sublist(0, end));
        final lengthMatch = RegExp(
          r'^Content-Length:\s*(\d+)',
          caseSensitive: false,
          multiLine: true,
        ).firstMatch(header);
        final length = lengthMatch == null ? 0 : int.parse(lengthMatch[1]!);
        if (length > 262144) {
          throw const FormatException('Corpo RTSP ultrapassou 256 KB.');
        }
        final total = end + 4 + length;
        if (_bytes.length >= total) {
          final reply = RtspReply.parse(_bytes.sublist(0, total));
          _bytes.removeRange(0, total);
          final received = int.tryParse(reply.headers['cseq'] ?? '');
          (result['respostas'] as List).add({
            'horario': DateTime.now().toUtc().toIso8601String(),
            'metodo': method,
            'autenticado': authorization != null,
            'status': reply.status,
            'duracaoMs': watch.elapsedMilliseconds,
            'cseqEnviado': sequence,
            'cseqRecebido': received,
            'cseqConfere': received == sequence,
            'servidor': reply.headers['server'],
            'metodos': reply.headers['public'],
            'tipoConteudo': reply.headers['content-type'],
            'tamanhoCorpo': length,
            if (lengthMatch == null)
              'aviso': 'Content-Length ausente; nenhum corpo foi presumido.',
          });
          return reply;
        }
      }
      if (_closed) {
        throw const FormatException(
          'A câmera encerrou a conexão antes de completar a resposta RTSP.',
        );
      }
      final changed = _changed ??= Completer<void>();
      await changed.future.timeout(_remaining());
    }
  }

  Future<Map<String, dynamic>> run(
    CameraConfig config, {
    Duration budget = const Duration(seconds: 6),
  }) async {
    _deadline = DateTime.now().add(budget);
    final watch = Stopwatch()..start();
    try {
      await _connect(config);
      await _request(config, 'OPTIONS');
      var reply = await _request(config, 'DESCRIBE');
      if (reply.status == 401) {
        final challenge = reply.headers['www-authenticate'] ?? '';
        final fields = parseChallenge(challenge);
        result['autenticacao'] = {
          'desafioRecebido': true,
          'esquema': challenge.toLowerCase().contains('digest ')
              ? 'Digest'
              : challenge.toLowerCase().contains('basic ')
              ? 'Basic'
              : 'desconhecido',
          'algoritmo': fields['algorithm'] ?? 'MD5',
          'qop': fields['qop'],
        };
        final authorization = rtspAuthorization(
          challenge,
          config,
          config.uri.replace(userInfo: '').toString(),
        );
        if (authorization != null) {
          reply = await _request(
            config,
            'DESCRIBE',
            authorization: authorization,
          );
        } else {
          result['avisoAutenticacao'] =
              'Desafio não suportado pelo teste direto; o motor de vídeo ainda será testado.';
        }
      }
      result['statusDescribe'] = reply.status;
      if (reply.status == 200) {
        result['descricaoRecebida'] = true;
        result['autenticacaoConfirmada'] = result.containsKey('autenticacao');
        final videoLines = reply.body.split(RegExp(r'\r?\n'));
        result['sdp'] = {
          'presente': reply.body.startsWith('v='),
          'videoAnunciado': videoLines.any((l) => l.startsWith('m=video ')),
          'audioAnunciado': videoLines.any((l) => l.startsWith('m=audio ')),
          'codecs': videoLines
              .where((l) => l.startsWith('a=rtpmap:'))
              .map((l) => l.substring(9))
              .take(16)
              .toList(),
          'bytes': utf8.encode(reply.body).length,
        };
      }
      result['etapa'] = 'concluido';
    } catch (error) {
      result['erro'] = {
        'tipo': error.runtimeType.toString(),
        'mensagem': error.toString(),
        'etapa': result['etapa'],
      };
    } finally {
      result['duracaoMs'] = watch.elapsedMilliseconds;
      _socket?.destroy();
      await _subscription?.cancel();
    }
    return result;
  }
}
