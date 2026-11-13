import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/camera_controls.dart' show HoldCameraButton;
import 'package:jortan_viewer/control_store.dart';
import 'package:jortan_viewer/daily_camera_controls.dart';
import 'package:jortan_viewer/design.dart';
import 'package:jortan_viewer/camera_joystick.dart';
import 'package:jortan_viewer/onvif.dart';

class MemoryControlStore extends ControlStore {
  ControlPreference? saved;
  bool joystick = false;
  @override
  Future<bool> loadJoystick() async => joystick;
  @override
  Future<void> saveJoystick(bool value) async {
    joystick = value;
  }

  @override
  Future<ControlPreference?> load(CameraConfig config) async =>
      saved?.matches(config) == true ? saved : null;
  @override
  Future<void> save(ControlPreference preference) async {
    saved = preference;
  }
}

class DailyClient extends OnvifClient {
  int inspections = 0, preparations = 0, moves = 0, stops = 0;
  bool fail = false, held = false;
  Completer<void>? pending;
  DailyClient(super.config, void Function(Map<String, dynamic>) event)
    : super(onEvent: event);
  @override
  Future<List<PtzProfile>> inspect({
    String? discoveredEndpoint,
    bool manualOnly = false,
  }) async {
    inspections++;
    expect(manualOnly, true);
    return [
      PtzProfile(
        'actual-token',
        'Perfil 1',
        Uri.parse('http://${config.host}:5000/onvif/deviceio_service'),
        VelocitySpace('', -1, 1, -1, 1, fraction: .1),
        null,
        capabilitySource: 'compatibilidade_yoosee_manual',
      ),
    ];
  }

  @override
  Future<void> prepareManual(
    PtzProfile profile, {
    bool? preferredMinimal,
    bool? preferredZeroStop,
  }) async {
    preparations++;
    expect(preferredMinimal, false);
    expect(preferredZeroStop, true);
    if (pending != null) await pending!.future;
    if (fail) {
      throw OnvifFailure(
        'parada_previa_falhou',
        'A câmera não confirmou a parada.',
      );
    }
  }

  @override
  bool? manualMinimalFormat(PtzProfile profile) => false;
  @override
  String? manualStopMethod(PtzProfile profile) =>
      'ContinuousMove_velocidade_zero';
  @override
  void setManualHold(PtzProfile profile, bool enabled) {
    held = enabled;
  }

  @override
  Future<void> move(PtzProfile profile, int x, int y, int z) async {
    moves++;
  }

  @override
  Future<void> stop(PtzProfile profile) async {
    stops++;
  }
}

void main() {
  testWidgets('Opção joystick persiste e botão Parar cancela arraste ativo', (
    tester,
  ) async {
    final store = MemoryControlStore();
    late DailyClient client;
    Widget screen() => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: DailyCameraControls(
            config: const CameraConfig(),
            enabled: true,
            store: store,
            onReport: (_) {},
            clientFactory: (c, e) => client = DailyClient(c, e),
          ),
        ),
      ),
    );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Joystick'));
    await tester.pumpAndSettle();
    expect(store.joystick, true);
    expect(find.byType(CameraJoystick), findsOneWidget);
    final control = find.byType(CameraJoystick);
    await tester.ensureVisible(control);
    final center = tester.getCenter(control);
    final gesture = await tester.startGesture(center);
    await gesture.moveTo(center + const Offset(64, 0));
    await tester.pump();
    expect(client.moves, 1);
    await tester.ensureVisible(find.text('Parar'));
    await tester.tap(find.text('Parar'));
    await tester.pump();
    final moves = client.moves;
    await gesture.moveTo(center + const Offset(-64, 0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(client.moves, moves);
    expect(client.stops, greaterThanOrEqualTo(1));
    await gesture.up();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.byType(CameraJoystick), findsOneWidget);
    expect(client.moves, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Conexão prepara sem mover, guarda controle e reutiliza após reconectar',
    (tester) async {
      final store = MemoryControlStore();
      final clients = <DailyClient>[];
      Map<String, dynamic> report = {};
      Widget screen(bool enabled) => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DailyCameraControls(
              config: const CameraConfig(),
              enabled: enabled,
              store: store,
              onReport: (r) => report = r,
              clientFactory: (c, e) {
                final client = DailyClient(c, e);
                clients.add(client);
                return client;
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(screen(false));
      await tester.pumpAndSettle();
      expect(clients, isEmpty);
      await tester.pumpWidget(screen(true));
      await tester.pumpAndSettle();
      expect(clients.single.inspections, 1);
      expect(clients.single.preparations, 1);
      expect(clients.single.moves, 0);
      expect(store.saved?.token, 'actual-token');
      expect(find.textContaining('Ativar teste'), findsNothing);
      expect(find.textContaining('experimental'), findsNothing);
      final control = find.byType(HoldCameraButton).at(2);
      await tester.ensureVisible(control);
      final gesture = await tester.startGesture(tester.getCenter(control));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 450));
      expect(clients.first.moves, 3);
      await gesture.up();
      await tester.pump();
      expect(clients.first.stops, 1);
      await tester.pumpWidget(screen(false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(screen(true));
      await tester.pumpAndSettle();
      expect(clients, hasLength(2));
      expect(clients.last.inspections, 0);
      expect(clients.last.preparations, 1);
      expect(clients.last.moves, 0);
      expect(report['resultado']['configuracaoReutilizada'], true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Resposta tardia em segundo plano não habilita movimento', (
    tester,
  ) async {
    final pending = Completer<void>();
    late DailyClient client;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DailyCameraControls(
              config: const CameraConfig(),
              enabled: true,
              store: MemoryControlStore(),
              onReport: (_) {},
              clientFactory: (c, e) =>
                  client = DailyClient(c, e)..pending = pending,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(client.preparations, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    pending.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<HoldCameraButton>(find.byType(HoldCameraButton).first)
          .enabled,
      false,
    );
    expect(client.moves, 0);
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'Parada recusada não salva nem libera setas; reconexão recupera',
    (tester) async {
      final store = MemoryControlStore();
      var fail = true;
      late DailyClient client;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DailyCameraControls(
                config: const CameraConfig(),
                enabled: true,
                store: store,
                onReport: (_) {},
                clientFactory: (c, e) =>
                    client = DailyClient(c, e)..fail = fail,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.saved, isNull);
      expect(client.moves, 0);
      expect(
        tester
            .widget<HoldCameraButton>(find.byType(HoldCameraButton).first)
            .enabled,
        false,
      );
      fail = false;
      await tester.ensureVisible(find.text('Reconectar controle'));
      await tester.tap(find.text('Reconectar controle'));
      await tester.pumpAndSettle();
      expect(store.saved, isNotNull);
      expect(
        tester
            .widget<HoldCameraButton>(find.byType(HoldCameraButton).first)
            .enabled,
        true,
      );
      expect(client.moves, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
