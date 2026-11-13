import 'dart:convert';

enum Transport { automatic, tcp, udp }

enum PlaybackTuning { compatible, responsive }

enum ViewingPreset { details, fluid }

class CameraConfig {
  final String host, username, password, path, onvifUrl;
  final int port;
  final Transport transport;
  final PlaybackTuning tuning;
  const CameraConfig({
    this.host = '192.168.1.100',
    this.port = 554,
    this.username = 'admin',
    this.password = '',
    this.path = '/onvif1',
    this.onvifUrl = '',
    this.transport = Transport.automatic,
    this.tuning = PlaybackTuning.compatible,
  });

  CameraConfig copyWith({String? path, PlaybackTuning? tuning}) => CameraConfig(
    host: host,
    port: port,
    username: username,
    password: password,
    path: path ?? this.path,
    onvifUrl: onvifUrl,
    transport: transport,
    tuning: tuning ?? this.tuning,
  );
  CameraConfig withPreset(ViewingPreset preset) => copyWith(
    path: preset == ViewingPreset.details ? '/onvif1' : '/onvif2',
    tuning: preset == ViewingPreset.details
        ? PlaybackTuning.compatible
        : PlaybackTuning.responsive,
  );
  ViewingPreset? get preset =>
      path == '/onvif1' && tuning == PlaybackTuning.compatible
      ? ViewingPreset.details
      : path == '/onvif2' && tuning == PlaybackTuning.responsive
      ? ViewingPreset.fluid
      : null;

  String? validate() {
    if (host.isEmpty || host.contains(RegExp(r'[\s/@?#:]'))) {
      return 'Informe um IP ou nome local, sem protocolo nem porta.';
    }
    if (port < 1 || port > 65535) return 'A porta deve estar entre 1 e 65535.';
    if (username.isEmpty) return 'Informe o usuário da câmera.';
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains(RegExp(r'[\s#]')) ||
        Uri.tryParse(path) == null) {
      return 'Use um caminho como /onvif1, sem espaços ou fragmentos.';
    }
    if (onvifUrl.isNotEmpty) {
      final endpoint = Uri.tryParse(onvifUrl);
      if (endpoint == null ||
          !['http', 'https'].contains(endpoint.scheme) ||
          endpoint.host != host ||
          endpoint.userInfo.isNotEmpty ||
          endpoint.hasQuery ||
          endpoint.hasFragment) {
        return 'A URL ONVIF deve usar HTTP/HTTPS e o mesmo IP da câmera, sem credenciais.';
      }
    }
    return null;
  }

  Uri get uri {
    final resource = Uri.parse(path);
    return Uri(
      scheme: 'rtsp',
      host: host,
      port: port,
      userInfo:
          '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}',
      path: resource.path,
      query: resource.hasQuery ? resource.query : null,
    );
  }

  List<Transport> get attempts => transport == Transport.automatic
      ? [Transport.tcp, Transport.udp]
      : [transport];

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'path': path,
    'transport': transport.name,
    'onvifUrl': onvifUrl,
    'tuning': tuning.name,
  };
  factory CameraConfig.fromJson(Map<String, dynamic> json) => CameraConfig(
    host: json['host'] as String,
    port: json['port'] as int,
    username: json['username'] as String,
    password: json['password'] as String,
    path: json['path'] as String,
    onvifUrl: json['onvifUrl'] as String? ?? '',
    transport: Transport.values.byName(json['transport'] as String),
    tuning:
        PlaybackTuning.values
            .where((v) => v.name == json['tuning'])
            .firstOrNull ??
        PlaybackTuning.compatible,
  );
}

/// Scrub before retaining a log, not just before exporting it.
class Redactor {
  final Set<String> _secrets = {};
  void add(CameraConfig config) {
    for (final secret in [
      config.password,
      '${config.username}:${config.password}',
    ]) {
      if (secret.isEmpty) continue;
      _secrets.addAll([
        secret,
        jsonEncode(secret).substring(1, jsonEncode(secret).length - 1),
        Uri.encodeComponent(secret),
        Uri.encodeQueryComponent(secret),
        base64Encode(utf8.encode(secret)),
      ]);
    }
  }

  String clean(String input) {
    var result = input.replaceAll(
      RegExp(r'''rtsps?://[^\s<>"']+''', caseSensitive: false),
      'rtsp://[omitido]',
    );
    result = result.replaceAll(
      RegExp(r'Authorization\s*:[^\r\n]*', caseSensitive: false),
      'Authorization: [omitida]',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'''\b(username|password|passwd|nonce|cnonce|response|opaque)\s*=\s*(?:"[^"]*"|[^\s,;]+)''',
        caseSensitive: false,
      ),
      (match) => '${match[1]}=[omitido]',
    );
    final sorted = _secrets.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final secret in sorted) {
      result = result.replaceAll(secret, '[omitido]');
      // Percent encodings may be logged in lower case.
      if (secret.contains('%')) {
        result = result.replaceAll(
          RegExp(RegExp.escape(secret), caseSensitive: false),
          '[omitido]',
        );
      }
    }
    return result;
  }
}

bool isTerminalPlayerError(String message) => RegExp(
  r'failed to recognize file format|failed to open|error opening|could not open|connection refused|network is unreachable|no route to host|server returned|method[^\n]*failed|no video or audio streams selected|loading failed',
  caseSensitive: false,
).hasMatch(message);

class DiagnosticFinding {
  final String code, message, confidence;
  final List<String> evidence, nextSteps;
  const DiagnosticFinding(
    this.code,
    this.message,
    this.confidence,
    this.evidence,
    this.nextSteps,
  );
  Map<String, dynamic> toJson() => {
    'codigo': code,
    'mensagem': message,
    'confianca': confidence,
    'evidencias': evidence,
    'proximosPassos': nextSteps,
  };
}

DiagnosticFinding diagnoseFailure(String details, {int? finalRtspStatus}) {
  final lines = details.split('\n');
  final text = details.toLowerCase();
  List<String> matching(RegExp pattern) =>
      lines.where(pattern.hasMatch).take(8).toList();
  final status404 = RegExp(
    r'(?:RTSP/1\.[01]\s+404|(?:method|DESCRIBE|SETUP|PLAY)[^\n]*\b404\b|404\s+Not Found)',
    caseSensitive: false,
  );
  final authentication = RegExp(
    r'(?:RTSP/1\.[01]\s+(?:401|403)|(?:method|DESCRIBE|SETUP|PLAY)[^\n]*\b(?:401|403)\b|401\s+Unauthorized|authentication failed)',
    caseSensitive: false,
  );
  // A successful challenge-response exchange may contain a normal initial 401.
  final statusMatches = RegExp(
    r'RTSP/1\.[01]\s+(\d{3})',
    caseSensitive: false,
  ).allMatches(details).toList();
  final lastStatus =
      finalRtspStatus ??
      (statusMatches.isEmpty ? null : int.parse(statusMatches.last[1]!));
  if (authentication.hasMatch(details) &&
      (lastStatus == null || lastStatus == 401 || lastStatus == 403)) {
    return DiagnosticFinding(
      'rtsp_authentication',
      'A câmera recusou o acesso. Confira usuário e senha local RTSP/ONVIF.',
      'evidencia_de_recusa',
      matching(authentication),
      [
        'Confira a senha local da câmera. Um desafio 401 inicial pode ser normal; consulte a última resposta autenticada.',
      ],
    );
  }
  if (status404.hasMatch(details) &&
      (lastStatus == null || lastStatus == 404)) {
    return DiagnosticFinding(
      'rtsp_path_not_found',
      'A câmera respondeu 404 para o caminho solicitado. Teste /onvif2 ou o caminho do fabricante.',
      'resposta_explicita',
      matching(status404),
      ['Confira o caminho RTSP no fabricante.'],
    );
  }
  if (text.contains('connection refused')) {
    return DiagnosticFinding(
      'tcp_refused',
      'A conexão foi recusada. Confira a porta e se o RTSP está habilitado.',
      'evidencia_de_rede',
      matching(RegExp('refused', caseSensitive: false)),
      ['Confira IP, porta e RTSP habilitado.'],
    );
  }
  if (text.contains('network is unreachable') ||
      text.contains('no route to host')) {
    return DiagnosticFinding(
      'network_unreachable',
      'A câmera não está acessível. Confira o Wi-Fi e o endereço IP.',
      'evidencia_de_rede',
      matching(RegExp('unreachable|no route', caseSensitive: false)),
      ['Confira o Wi-Fi e o isolamento de dispositivos.'],
    );
  }
  if (text.contains('nonmatching transport in server reply')) {
    return DiagnosticFinding(
      'rtsp_transport_mismatch',
      'A câmera aceitou a sessão, mas declarou um transporte diferente do solicitado no SETUP.',
      'erro_explicito_do_motor',
      matching(
        RegExp('Nonmatching transport|Transport:', caseSensitive: false),
      ),
      [
        'Confira a compatibilidade TCP e os cabeçalhos solicitado/recebido.',
        'Esse erro ocorre antes de receber vídeo e não indica senha incorreta.',
      ],
    );
  }
  if (text.contains('461 unsupported transport') ||
      text.contains('unsupported transport')) {
    return DiagnosticFinding(
      'rtsp_transport_rejected',
      'A câmera rejeitou o transporte solicitado.',
      'resposta_explicita',
      matching(RegExp('transport', caseSensitive: false)),
      ['Compare TCP e UDP.'],
    );
  }
  if (RegExp(
    r'cseq[^\n]*(?:expected|received|divergente)',
    caseSensitive: false,
  ).hasMatch(details)) {
    return DiagnosticFinding(
      'rtsp_sequence_mismatch',
      'A resposta RTSP veio com uma sequência CSeq inesperada. Há um indício de incompatibilidade na negociação; o caminho ainda não foi comprovado como inválido.',
      'indicio',
      matching(RegExp(r'CSeq', caseSensitive: false)),
      [
        'Compare as respostas OPTIONS/DESCRIBE do teste direto com o log do reprodutor.',
        'Um CSeq diferente pode ser apenas um aviso; verifique também o código RTSP final e o SDP.',
      ],
    );
  }
  if (RegExp(
    r'width=0.*height=0|Could not find codec parameters[^\n]*unspecified size|Could not extract VPS/PPS/SPS',
    caseSensitive: false,
  ).hasMatch(details)) {
    return DiagnosticFinding(
      'video_parameters_missing',
      'A sessão RTSP foi aberta, mas faltaram parâmetros para iniciar o vídeo. O motor ainda não conhecia as dimensões/quadros de referência; isso não comprova senha incorreta nem codec incompatível.',
      'evidencia_do_motor',
      matching(
        RegExp(
          r'width=0|codec parameters|VPS/PPS/SPS|Could not open codec',
          caseSensitive: false,
        ),
      ),
      [
        'Compare TCP e UDP e aguarde os parâmetros do próximo quadro-chave.',
        'Verifique o tempo de análise registrado no motor.',
      ],
    );
  }
  if (text.contains('failed to recognize file format') ||
      text.contains('avformat_open_input() failed')) {
    return DiagnosticFinding(
      'rtsp_open_failed',
      'O reprodutor não conseguiu abrir a sessão RTSP. Esse erro não comprova caminho inválido nem codec incompatível.',
      'causa_indeterminada',
      matching(
        RegExp(
          'recognize file format|avformat_open_input',
          caseSensitive: false,
        ),
      ),
      [
        'Consulte o teste direto: resposta RTSP, autenticação e presença de SDP.',
        'Se o teste direto retornar SDP e o reprodutor falhar, investigue compatibilidade entre o firmware e o motor de vídeo.',
      ],
    );
  }
  if (text.contains('decoder') || text.contains('codec not found')) {
    return DiagnosticFinding(
      'decoder_error',
      'O motor relatou um problema no decodificador. Verifique o codec e as mensagens anteriores.',
      'indicio',
      matching(RegExp('decoder|codec not found', caseSensitive: false)),
      ['Confira o codec informado no SDP e os erros de decodificação.'],
    );
  }
  return const DiagnosticFinding(
    'undetermined',
    'Não chegou vídeo reproduzível. O diagnóstico ainda não identifica a causa; este resultado não comprova bloqueio de firewall.',
    'causa_indeterminada',
    [],
    ['Confira o teste TCP, as respostas RTSP, o SDP e as etapas do reprodutor.'],
  );
}

String explainFailure(String details) => diagnoseFailure(details).message;

class Attempt {
  final String transport;
  final int round;
  final DateTime started = DateTime.now().toUtc();
  DateTime? ended;
  bool videoReceived = false;
  String result = 'Em andamento';
  final List<String> logs = [];
  final List<Map<String, dynamic>> events = [];
  final Map<String, dynamic> checks = {};
  DiagnosticFinding? finding;
  int droppedLogs = 0;
  final List<String> importantLogs = [];
  String stage = 'inicializacao';
  int? lastRtspStatus;
  void addLog(String message) {
    final statuses = RegExp(r'RTSP/1\.[01]\s+(\d{3})').allMatches(message);
    if (statuses.isNotEmpty) lastRtspStatus = int.parse(statuses.last[1]!);
    if (RegExp(r'rtsp: ret=-?\d+ c=').hasMatch(message) ||
        message.trim().endsWith(': ]')) {
      droppedLogs++;
      return;
    }
    if (RegExp(
          r'error|failed|could not|invalid|denied|CSeq|RTSP/1\.',
          caseSensitive: false,
        ).hasMatch(message) &&
        !importantLogs.contains(message)) {
      if (importantLogs.length >= 100) importantLogs.removeAt(30);
      importantLogs.add(
        message.length > 2500 ? message.substring(0, 2500) : message,
      );
    }
    if (logs.length >= 320) {
      logs.removeAt(80);
      droppedLogs++;
    }
    logs.add(
      message.length > 2500
          ? '${message.substring(0, 2500)} [linha truncada]'
          : message,
    );
  }

  void event(String name, [Map<String, dynamic> data = const {}]) {
    stage = name;
    if (events.length < 100) {
      events.add({
        'horario': DateTime.now().toUtc().toIso8601String(),
        'etapa': name,
        ...data,
      });
    }
  }

  Attempt(this.transport, this.round);
  Map<String, dynamic> toJson() => {
    'transporte': transport,
    'rodada': round,
    'inicio': started.toIso8601String(),
    'fim': ended?.toIso8601String(),
    'duracaoMs': (ended ?? DateTime.now().toUtc())
        .difference(started)
        .inMilliseconds,
    'videoRecebido': videoReceived,
    'resultado': result,
    'detalhes': logs,
    'linhasDescartadas': droppedLogs,
    'errosEAvisosPreservados': importantLogs,
    'ultimoStatusRtsp': lastRtspStatus,
    'etapa': stage,
    'eventos': events,
    'verificacoes': checks,
    'diagnostico': finding?.toJson(),
  };
}
