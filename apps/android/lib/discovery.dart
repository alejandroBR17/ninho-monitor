import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:xml/xml.dart';

int ipv4Number(String address) {
  final pieces = address.split('.');
  if (pieces.length != 4) throw const FormatException('Informe uma rede IPv4.');
  var number = 0;
  for (final piece in pieces) {
    final value = int.tryParse(piece);
    if (value == null ||
        value < 0 ||
        value > 255 ||
        piece != value.toString()) {
      throw const FormatException('Endereço IPv4 inválido.');
    }
    number = (number << 8) | value;
  }
  return number;
}

String ipv4Text(int number) =>
    [24, 16, 8, 0].map((shift) => (number >> shift) & 255).join('.');
bool privateIpv4(int ip) =>
    (ip >> 24) == 10 ||
    (ip >> 20) == 0xac1 ||
    (ip >> 16) == 0xc0a8 ||
    (ip >> 16) == 0xa9fe;

class DiscoveryRange {
  final int network, prefix;
  DiscoveryRange._(this.network, this.prefix);
  factory DiscoveryRange.parse(String input) {
    final parts = input.trim().split('/');
    if (parts.length != 2) {
      throw const FormatException('Use uma faixa como 192.168.1.0/24.');
    }
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 24 || prefix > 32) {
      throw const FormatException(
        'Use /24 até /32: a busca é limitada a 254 endereços por vez.',
      );
    }
    final ip = ipv4Number(parts[0]);
    final mask = (0xffffffff << (32 - prefix)) & 0xffffffff;
    final network = ip & mask;
    final last = network + ((1 << (32 - prefix)) - 1);
    if (!privateIpv4(network) || !privateIpv4(last)) {
      throw const FormatException(
        'A busca aceita apenas sua rede privada ou link-local.',
      );
    }
    return DiscoveryRange._(network, prefix);
  }
  List<String> get hosts {
    final last = network + ((1 << (32 - prefix)) - 1);
    final firstHost = prefix >= 31 ? network : network + 1;
    final lastHost = prefix >= 31 ? last : last - 1;
    return [for (var ip = firstHost; ip <= lastHost; ip++) ipv4Text(ip)];
  }

  bool contains(String ip) {
    try {
      final number = ipv4Number(ip);
      return number >= network && number < network + (1 << (32 - prefix));
    } on FormatException {
      return false;
    }
  }

  @override
  String toString() => '${ipv4Text(network)}/$prefix';
}

class DiscoveryDevice {
  final String host;
  final Map<int, int> rtspStatuses;
  final String? name, onvifEndpoint;
  final bool onvif;
  const DiscoveryDevice(
    this.host, {
    this.rtspStatuses = const {},
    this.name,
    this.onvifEndpoint,
    this.onvif = false,
  });
  int get port => rtspStatuses.containsKey(554)
      ? 554
      : rtspStatuses.isEmpty
      ? 554
      : (rtspStatuses.keys.toList()..sort()).first;
  bool get rtspConfirmed => rtspStatuses.isNotEmpty;
  DiscoveryDevice merge(DiscoveryDevice other) => DiscoveryDevice(
    host,
    rtspStatuses: {...rtspStatuses, ...other.rtspStatuses},
    name: other.name ?? name,
    onvifEndpoint: other.onvifEndpoint ?? onvifEndpoint,
    onvif: onvif || other.onvif,
  );
  Map<String, dynamic> toJson() => {
    'ip': host,
    'portaSugerida': port,
    'rtspConfirmado': rtspConfirmed,
    'respostasRtsp': rtspStatuses.map((key, value) => MapEntry('$key', value)),
    'onvif': onvif,
    'nome': name,
    'servicoOnvif': onvifEndpoint,
  };
}

List<DiscoveryDevice> parseDiscoveryReply(
  String source,
  String xml,
  String messageId,
  DiscoveryRange range,
) {
  if (!range.contains(source) || xml.length > 65536) return const [];
  try {
    final document = XmlDocument.parse(xml);
    final relates = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'RelatesTo')
        .firstOrNull
        ?.innerText
        .trim();
    if (relates != null && relates != messageId) return const [];
    final result = <DiscoveryDevice>[];
    for (final match in document.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'ProbeMatch',
    )) {
      String value(String name) =>
          match.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == name)
              .firstOrNull
              ?.innerText
              .trim() ??
          '';
      final addresses = value('XAddrs').split(RegExp(r'\s+'));
      final endpoint = addresses
          .map(Uri.tryParse)
          .whereType<Uri>()
          .where(
            (uri) =>
                ['http', 'https'].contains(uri.scheme) &&
                uri.host == source &&
                uri.userInfo.isEmpty,
          )
          .firstOrNull;
      final types = value('Types');
      if (!types.contains('NetworkVideoTransmitter') &&
          (endpoint == null ||
              !endpoint.path.toLowerCase().contains('onvif'))) {
        continue;
      }
      String? name;
      for (final scope in value('Scopes').split(RegExp(r'\s+'))) {
        final uri = Uri.tryParse(scope);
        if (uri != null && uri.path.startsWith('/name/')) {
          name = Uri.decodeComponent(
            uri.path.substring(6),
          ).replaceAll(RegExp(r'[\x00-\x1f]'), '');
          if (name.length > 80) name = name.substring(0, 80);
          break;
        }
      }
      result.add(
        DiscoveryDevice(
          source,
          onvif: true,
          name: name,
          onvifEndpoint: endpoint?.toString(),
        ),
      );
    }
    return result;
  } on FormatException {
    return const [];
  }
}

class DiscoveryReport {
  final String range;
  final List<int> ports;
  final DateTime started = DateTime.now().toUtc();
  DateTime? ended;
  int completed = 0, total = 0;
  bool cancelled = false;
  final Map<String, DiscoveryDevice> devices = {};
  final Set<String> warnings = {};
  DiscoveryReport(this.range, this.ports);
  List<DiscoveryDevice> get found =>
      devices.values.toList()
        ..sort((a, b) => ipv4Number(a.host).compareTo(ipv4Number(b.host)));
  Map<String, dynamic> toJson() => {
    'faixa': range,
    'portas': ports,
    'inicio': started.toIso8601String(),
    'fim': ended?.toIso8601String(),
    'testesConcluidos': completed,
    'totalTestes': total,
    'cancelada': cancelled,
    'avisos': warnings.toList(),
    'dispositivos': found.map((d) => d.toJson()).toList(),
    'metodos': [
      'OPTIONS RTSP sem senha',
      'WS-Discovery unicast; sem multicast',
    ],
    'limite':
        'Nem toda câmera responde à descoberta. Porta aberta sem resposta RTSP não é identificada como câmera.',
  };
}

typedef DiscoveryProbe =
    Future<DiscoveryDevice?> Function(String host, int port);

class CameraDiscovery {
  final Duration connectTimeout, replyTimeout;
  final int concurrency;
  final DiscoveryProbe? probeOverride;
  CameraDiscovery({
    this.connectTimeout = const Duration(milliseconds: 450),
    this.replyTimeout = const Duration(milliseconds: 700),
    this.concurrency = 24,
    this.probeOverride,
  });
  final Set<Socket> _sockets = {};
  RawDatagramSocket? _udp;
  Completer<void>? _udpFinished;
  bool _cancelled = false, _running = false;
  final Set<String> _warnings = {};
  void cancel() {
    _cancelled = true;
    for (final socket in _sockets.toList()) {
      socket.destroy();
    }
    _udp?.close();
    if (_udpFinished != null && !_udpFinished!.isCompleted) {
      _udpFinished!.complete();
    }
  }

  static Future<List<String>> localRanges() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final ranges = <String>{};
    for (final item in interfaces) {
      if (!RegExp(
        r'^(?:wlan|wifi|en\d|eth|ap\d)',
        caseSensitive: false,
      ).hasMatch(item.name)) {
        continue;
      }
      for (final address in item.addresses) {
        final ip = ipv4Number(address.address);
        if (privateIpv4(ip)) {
          ranges.add(DiscoveryRange.parse('${address.address}/24').toString());
        }
      }
    }
    return ranges.toList();
  }

  Future<DiscoveryDevice?> probeRtsp(String host, int port) async {
    Socket? socket;
    StreamSubscription<List<int>>? reading;
    try {
      if (_cancelled) return null;
      socket = await Socket.connect(host, port, timeout: connectTimeout);
      if (_cancelled) {
        socket.destroy();
        return null;
      }
      _sockets.add(socket);
      unawaited(
        socket.done.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
      final response = Completer<int?>();
      final bytes = <int>[];
      reading = socket.listen(
        (data) {
          if (response.isCompleted) return;
          bytes.addAll(data);
          if (bytes.length > 16384) {
            response.complete(null);
            return;
          }
          final text = latin1.decode(bytes);
          final end = text.indexOf('\r\n');
          if (end < 0) return;
          final status = RegExp(
            r'^RTSP/1\.[01]\s+(\d{3})(?:\s|$)',
          ).firstMatch(text.substring(0, end));
          response.complete(status == null ? null : int.parse(status[1]!));
        },
        onDone: () {
          if (!response.isCompleted) response.complete(null);
        },
        onError: (Object error) {
          if (!response.isCompleted) response.complete(null);
        },
      );
      socket.add(
        ascii.encode(
          'OPTIONS rtsp://$host:$port/ RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: JortanViewer-Discovery/1.3\r\n\r\n',
        ),
      );
      final status = await response.future.timeout(
        replyTimeout,
        onTimeout: () => null,
      );
      if (_cancelled || status == null) return null;
      return DiscoveryDevice(host, rtspStatuses: {port: status});
    } on SocketException catch (error) {
      if ([1, 13].contains(error.osError?.errorCode)) {
        _warnings.add(
          'A rede local recusou uma operação. Confira a permissão de Rede Local e o Wi-Fi.',
        );
      }
      return null;
    } on TimeoutException {
      return null;
    } finally {
      if (socket != null) _sockets.remove(socket);
      socket?.destroy();
      await reading?.cancel();
    }
  }

  Future<void> _discoverOnvif(
    DiscoveryRange range,
    void Function(DiscoveryDevice) found,
  ) async {
    StreamSubscription<RawSocketEvent>? reading;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      if (_cancelled) {
        socket.close();
        return;
      }
      _udp = socket;
      _udpFinished = Completer<void>();
      final random = Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final messageId =
          'urn:uuid:${id.substring(0, 8)}-${id.substring(8, 12)}-4${id.substring(13, 16)}-8${id.substring(17, 20)}-${id.substring(20)}';
      final packet = utf8.encode(
        '''<?xml version="1.0" encoding="UTF-8"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://schemas.xmlsoap.org/ws/2004/08/addressing" xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" xmlns:dn="http://www.onvif.org/ver10/network/wsdl"><s:Header><a:MessageID>$messageId</a:MessageID><a:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</a:To><a:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</a:Action></s:Header><s:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></s:Body></s:Envelope>''',
      );
      reading = socket.listen(
        (event) {
          if (event != RawSocketEvent.read || _cancelled) return;
          Datagram? datagram;
          while ((datagram = socket.receive()) != null) {
            final data = datagram!;
            for (final device in parseDiscoveryReply(
              data.address.address,
              utf8.decode(data.data, allowMalformed: true),
              messageId,
              range,
            )) {
              found(device);
            }
          }
        },
        onError: (Object error) {
          _warnings.add(
            'A descoberta ONVIF não respondeu corretamente; a busca RTSP continua.',
          );
        },
      );
      var count = 0;
      for (final host in range.hosts) {
        if (_cancelled) break;
        socket.send(packet, InternetAddress(host), 3702);
        if (++count % 8 == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 15));
        }
      }
      if (!_cancelled) {
        await _udpFinished!.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
      }
    } on SocketException {
      if (!_cancelled) {
        _warnings.add(
          'Não foi possível usar descoberta ONVIF unicast; a busca RTSP foi mantida.',
        );
      }
    } finally {
      _udp?.close();
      _udp = null;
      await reading?.cancel();
    }
  }

  Future<DiscoveryReport> search(
    DiscoveryRange range, {
    List<int> ports = const [554, 8554],
    void Function(DiscoveryReport)? onUpdate,
    bool onvif = true,
  }) async {
    if (_running) throw StateError('Já existe uma busca em andamento.');
    final selected = ports.toSet().toList();
    if (selected.isEmpty ||
        selected.length > 3 ||
        selected.any((p) => p < 1 || p > 65535)) {
      throw const FormatException('Escolha até três portas RTSP válidas.');
    }
    if (concurrency < 1 || concurrency > 32) {
      throw const FormatException('Concorrência de busca inválida.');
    }
    _running = true;
    _cancelled = false;
    _warnings.clear();
    final report = DiscoveryReport(range.toString(), selected);
    final jobs = [
      for (final host in range.hosts)
        for (final port in selected) (host, port),
    ];
    report.total = jobs.length;
    final watch = Stopwatch()..start();
    var lastUpdate = -1000;
    void emit({bool force = false}) {
      report.warnings.addAll(_warnings);
      if (force || watch.elapsedMilliseconds - lastUpdate >= 100) {
        lastUpdate = watch.elapsedMilliseconds;
        onUpdate?.call(report);
      }
    }

    void found(DiscoveryDevice device) {
      if (_cancelled) return;
      report.devices[device.host] =
          report.devices[device.host]?.merge(device) ?? device;
      emit(force: true);
    }

    var cursor = 0;
    Future<void> worker() async {
      while (!_cancelled && cursor < jobs.length) {
        final job = jobs[cursor++];
        final device = await (probeOverride ?? probeRtsp)(job.$1, job.$2);
        if (device != null) found(device);
        report.completed++;
        emit();
      }
    }

    try {
      emit(force: true);
      await Future.wait([
        if (onvif) _discoverOnvif(range, found),
        for (var index = 0; index < min(concurrency, jobs.length); index++)
          worker(),
      ]);
    } finally {
      _running = false;
      report.cancelled = _cancelled;
      report.ended = DateTime.now().toUtc();
      emit(force: true);
    }
    return report;
  }
}
