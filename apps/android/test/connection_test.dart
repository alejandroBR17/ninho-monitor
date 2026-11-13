import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/connection.dart';
import 'package:jortan_viewer/playback.dart';
import 'package:jortan_viewer/version.dart';

class FakeSession implements PlaybackSession {
  final frame = Completer<void>();
  final bus = StreamController<PlaybackEvent>.broadcast();
  bool closed = false;
  Transport? used;
  final bool render;
  final String? rejection;
  FakeSession({this.render = false, this.rejection});
  @override
  VideoController? get video => null;
  @override
  Future<void> get firstFrame => frame.future;
  @override
  Stream<PlaybackEvent> get events => bus.stream;
  @override
  Future<void> open(CameraConfig config, Transport transport) async {
    used = transport;
    if (rejection != null) {
      bus.add(PlaybackEvent(PlaybackEventKind.failure, rejection!));
    } else if (render) {
      frame.complete();
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    await bus.close();
  }
}

class AudioFakeSession extends FakeSession implements AudioPlaybackSession {
  final List<bool> changes = [];
  bool rejectAudio = false;
  AudioFakeSession() : super(render: true);
  @override
  Future<void> setAudioEnabled(bool enabled) async {
    if (rejectAudio) throw StateError('fixture audio failure');
    changes.add(enabled);
  }
}

class CaptureFakeSession extends FakeSession implements CapturePlaybackSession {
  Completer<Uint8List?> capture = Completer<Uint8List?>();
  CaptureFakeSession() : super(render: true);
  @override
  Future<Uint8List?> captureFrame() => capture.future;
}

Future<void> until(bool Function() predicate) async {
  for (var i = 0; i < 200; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('O estado esperado não chegou.');
}

void main() {
  test(
    'Captura exige vídeo ativo e descarta imagem de uma sessão encerrada',
    () async {
      final fake = CaptureFakeSession();
      final connection = CameraConnection(factory: () => fake);
      await expectLater(connection.captureFrame(), throwsStateError);
      await connection.connect(const CameraConfig(transport: Transport.tcp));
      await until(() => connection.phase == ConnectionPhase.live);
      final first = connection.captureFrame();
      fake.capture.complete(Uint8List.fromList([137, 80, 78, 71]));
      expect(await first, [137, 80, 78, 71]);
      fake.capture = Completer<Uint8List?>();
      final pending = connection.captureFrame();
      final assertion = expectLater(pending, throwsStateError);
      await connection.disconnect();
      fake.capture.complete(Uint8List.fromList([137, 80, 78, 71]));
      await assertion;
      connection.dispose();
    },
  );
  test(
    'Resumo preserva motivo do controle e remove credenciais/logs extensos',
    () {
      final connection = CameraConnection(factory: () => FakeSession());
      connection.redactor.add(const CameraConfig(password: 'fixture-private'));
      connection.attempts.add(
        Attempt('tcp', 0)..addLog('registro extenso que não deve entrar'),
      );
      connection.controlsReport = {
        'resultado': {'ultimoErro': 'ptz_capacidades_indeterminadas'},
        'eventos': [
          {
            'falhaSoap': 'SOAPFault',
            'motivos': ['fixture-private recusada'],
          },
          ...List.generate(
            60,
            (i) => {'codigo': 'http_conexao_encerrada', 'indice': i},
          ),
        ],
      };
      final brief = connection.briefReport();
      final json = jsonDecode(brief) as Map;
      expect((json['eventosControle'] as List).length, 9);
      expect(brief, isNot(contains('fixture-private')));
      expect(brief, isNot(contains('registro extenso')));
      expect(brief, contains('ptz_capacidades_indeterminadas'));
      connection.dispose();
    },
  );

  test(
    'Escuta começa silenciada, alterna sem desconectar e falha de áudio não encerra vídeo',
    () async {
      final fake = AudioFakeSession();
      final connection = CameraConnection(factory: () => fake);
      await connection.toggleAudio();
      expect(fake.changes, isEmpty);
      await connection.connect(const CameraConfig(transport: Transport.tcp));
      await until(() => connection.phase == ConnectionPhase.live);
      expect(connection.audioEnabled, false);
      await connection.toggleAudio();
      expect(connection.audioEnabled, true);
      await connection.toggleAudio();
      expect(connection.audioEnabled, false);
      expect(fake.changes, [true, false]);
      fake.rejectAudio = true;
      await connection.toggleAudio();
      expect(connection.audioError, isNotNull);
      expect(connection.phase, ConnectionPhase.live);
      expect(connection.audioEnabled, false);
      await connection.disconnect();
      connection.dispose();
    },
  );

  test(
    'Disponibilidade de áudio acompanha o fluxo e volta a desconhecida ao reconectar',
    () async {
      final sessions = <AudioFakeSession>[];
      final connection = CameraConnection(
        factory: () {
          final session = AudioFakeSession();
          sessions.add(session);
          return session;
        },
      );
      await connection.connect(const CameraConfig(transport: Transport.tcp));
      await until(() => connection.phase == ConnectionPhase.live);
      sessions.last.bus.add(
        const PlaybackEvent(PlaybackEventKind.diagnostic, 'teste_rtsp', {
          'sdp': {'presente': true, 'audioAnunciado': false},
        }),
      );
      await until(() => connection.audioAvailable == false);
      await connection.toggleAudio();
      expect(sessions.last.changes, isEmpty);
      expect(connection.phase, ConnectionPhase.live);
      sessions.last.bus.add(
        const PlaybackEvent(
          PlaybackEventKind.diagnostic,
          'disponibilidade_audio',
          {'disponivel': true},
        ),
      );
      await until(() => connection.audioAvailable == true);
      await connection.toggleAudio();
      expect(sessions.last.changes, [true]);
      await connection.disconnect();
      expect(connection.audioAvailable, isNull);
      await connection.connect(const CameraConfig(transport: Transport.tcp));
      await until(() => connection.phase == ConnectionPhase.live);
      expect(connection.audioAvailable, isNull);
      await connection.toggleAudio();
      expect(sessions.last.changes, [true]);
      await connection.disconnect();
      connection.dispose();
    },
  );

  test('Abrir o RTSP não basta: aguarda primeiro quadro', () async {
    final fake = FakeSession();
    final connection = CameraConnection(
      transportCooldown: Duration.zero,
      factory: () => fake,
    );
    await connection.connect(const CameraConfig(transport: Transport.tcp));
    await until(() => fake.used != null);
    expect(connection.phase, ConnectionPhase.connecting);
    fake.frame.complete();
    await until(() => connection.phase == ConnectionPhase.live);
    expect(connection.attempts.single.videoReceived, isTrue);
    await connection.disconnect();
    expect(fake.closed, isTrue);
    expect(connection.phase, ConnectionPhase.idle);
    connection.dispose();
  });
  test('TCP sem quadros é fechado antes de tentar UDP', () async {
    final first = FakeSession();
    final second = FakeSession(render: true);
    var calls = 0;
    final connection = CameraConnection(
      transportCooldown: Duration.zero,
      frameTimeout: const Duration(milliseconds: 15),
      factory: () {
        calls++;
        if (calls == 2) expect(first.closed, isTrue);
        return calls == 1 ? first : second;
      },
    );
    await connection.connect(const CameraConfig());
    await until(() => connection.phase == ConnectionPhase.live);
    expect(first.used, Transport.tcp);
    expect(second.used, Transport.udp);
    expect(connection.attempts.map((a) => a.videoReceived), [false, true]);
    await connection.disconnect();
    connection.dispose();
  });
  test('Autenticação recusada mantém evidência por transporte', () async {
    final connection = CameraConnection(
      transportCooldown: Duration.zero,
      factory: () => FakeSession(rejection: 'RTSP 401 Unauthorized'),
    );
    await connection.connect(const CameraConfig());
    await until(() => connection.phase == ConnectionPhase.failed);
    expect(connection.message, contains('recusou o acesso'));
    expect(connection.attempts, hasLength(2));
    expect(connection.attempts.every((a) => a.ended != null), isTrue);
    await connection.disconnect();
    connection.dispose();
  });
  test(
    'Cancelar durante espera não inicia fallback nem altera estado depois',
    () async {
      var calls = 0;
      final fake = FakeSession();
      final connection = CameraConnection(
        transportCooldown: Duration.zero,
        factory: () {
          calls++;
          return fake;
        },
        frameTimeout: const Duration(milliseconds: 20),
      );
      await connection.connect(const CameraConfig());
      await until(() => fake.used != null);
      await connection.disconnect();
      fake.frame.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls, 1);
      expect(fake.closed, isTrue);
      expect(connection.phase, ConnectionPhase.idle);
      connection.dispose();
    },
  );
  test('Perda de vídeo permite exatamente três reconexões', () async {
    final sessions = <FakeSession>[];
    final connection = CameraConnection(
      transportCooldown: Duration.zero,
      factory: () {
        final fake = FakeSession(render: true);
        sessions.add(fake);
        return fake;
      },
      retryDelays: List.filled(3, const Duration(milliseconds: 1)),
    );
    await connection.connect(const CameraConfig(transport: Transport.tcp));
    for (var i = 0; i < 4; i++) {
      await until(
        () =>
            sessions.length == i + 1 &&
            connection.phase == ConnectionPhase.live,
      );
      sessions[i].bus.add(
        const PlaybackEvent(PlaybackEventKind.failure, 'Connection lost'),
      );
    }
    await until(() => connection.phase == ConnectionPhase.failed);
    expect(sessions, hasLength(4));
    expect(sessions.every((s) => s.closed), isTrue);
    await connection.disconnect();
    connection.dispose();
  });
  test(
    'Cancelar durante intervalo de reconexão encerra novas tentativas',
    () async {
      var calls = 0;
      final fake = FakeSession(render: true);
      final connection = CameraConnection(
        transportCooldown: Duration.zero,
        factory: () {
          calls++;
          return fake;
        },
        retryDelays: [const Duration(milliseconds: 60)],
      );
      await connection.connect(const CameraConfig(transport: Transport.tcp));
      await until(() => connection.phase == ConnectionPhase.live);
      fake.bus.add(const PlaybackEvent(PlaybackEventKind.failure, 'Lost'));
      await until(() => connection.phase == ConnectionPhase.reconnecting);
      await connection.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(calls, 1);
      expect(connection.phase, ConnectionPhase.idle);
      connection.dispose();
    },
  );
  test('Vídeo que deixa de avançar dispara reconexão', () async {
    var calls = 0;
    final connection = CameraConnection(
      transportCooldown: Duration.zero,
      factory: () {
        calls++;
        return FakeSession(render: true);
      },
      stallTimeout: const Duration(milliseconds: 12),
      retryDelays: [const Duration(milliseconds: 1)],
    );
    await connection.connect(const CameraConfig(transport: Transport.tcp));
    await until(() => calls == 2);
    await connection.disconnect();
    connection.dispose();
  });
  test('Relatório remove senha crua, codificada e URL completa', () async {
    const secret = 'p@ss:/?&ab';
    const config = CameraConfig(
      password: secret,
      path: '/onvif1?token=p%40ss%3A%2F%3F%26ab',
      transport: Transport.tcp,
    );
    final fake = FakeSession();
    final connection = CameraConnection(
      transportCooldown: Duration.zero,
      factory: () => fake,
    );
    await connection.connect(config);
    await until(() => fake.used != null);
    fake.bus.add(
      PlaybackEvent(
        PlaybackEventKind.log,
        '${config.uri} password=$secret encoded=${Uri.encodeComponent(secret)}\nAuthorization: Basic ${base64Encode(utf8.encode('admin:$secret'))}',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 4));
    await connection.disconnect();
    final report = connection.report();
    expect(report, isNot(contains(secret)));
    expect(report, isNot(contains(Uri.encodeComponent(secret))));
    expect(report, isNot(contains(base64Encode(utf8.encode('admin:$secret')))));
    expect(jsonDecode(report), isA<Map>());
    connection.dispose();
  });
  test('Toques simultâneos não abrem duas capturas', () async {
    var calls = 0;
    final connection = CameraConnection(
      transportCooldown: Duration.zero,
      factory: () {
        calls++;
        return FakeSession(render: true);
      },
    );
    await Future.wait([
      connection.connect(
        const CameraConfig(host: '192.168.1.10', transport: Transport.tcp),
      ),
      connection.connect(
        const CameraConfig(host: '192.168.1.100', transport: Transport.tcp),
      ),
    ]);
    await until(() => connection.phase == ConnectionPhase.live);
    expect(calls, 1);
    expect(connection.config.host, '192.168.1.100');
    await connection.disconnect();
    expect(connection.session, isNull);
    connection.dispose();
  });
  test(
    'Eventos estruturados e avisos opcionais não encerram o vídeo',
    () async {
      final fake = FakeSession();
      final connection = CameraConnection(
        transportCooldown: Duration.zero,
        factory: () => fake,
      );
      await connection.connect(
        const CameraConfig(
          password: 'private-password',
          transport: Transport.tcp,
        ),
      );
      await until(() => fake.used != null);
      fake.bus.add(
        const PlaybackEvent(
          PlaybackEventKind.diagnostic,
          'aviso_de_propriedade',
          {'mensagem': 'property not found osc', 'fatal': false},
        ),
      );
      fake.bus.add(
        const PlaybackEvent(PlaybackEventKind.diagnostic, 'teste_rtsp', {
          'statusDescribe': 200,
          'respostas': [
            {'metodo': 'DESCRIBE', 'status': 401, 'autenticado': false},
            {'metodo': 'DESCRIBE', 'status': 200, 'autenticado': true},
          ],
          'autenticacaoConfirmada': true,
        }),
      );
      fake.frame.complete();
      await until(() => connection.phase == ConnectionPhase.live);
      expect(connection.phase, ConnectionPhase.live);
      expect(connection.attempts.single.checks['teste_rtsp'], isNotNull);
      expect(
        connection.attempts.single.logs.join(),
        isNot(contains('RTSP/1.0 401')),
      );
      final report = jsonDecode(connection.report()) as Map;
      expect(report['schemaDiagnostico'], 2);
      expect(report['produto'], 'Jortan Viewer $appVersion');
      await connection.disconnect();
      connection.dispose();
    },
  );
  test('Configuração inválida não cria reprodutor', () async {
    var called = false;
    final connection = CameraConnection(
      transportCooldown: Duration.zero,
      factory: () {
        called = true;
        return FakeSession();
      },
    );
    await connection.connect(const CameraConfig(host: 'rtsp://192.168.1.100'));
    expect(called, isFalse);
    expect(connection.phase, ConnectionPhase.failed);
    connection.dispose();
  });
}
