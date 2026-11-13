import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/camera_controls.dart';
import 'package:jortan_viewer/onvif.dart';
import 'package:jortan_viewer/design.dart';

const generic =
    'http://www.onvif.org/ver10/tptz/PanTiltSpaces/VelocityGenericSpace';

class ProfileClient extends OnvifClient {
  int moves = 0, stops = 0;
  ProfileClient(super.config, void Function(Map<String, dynamic>) event)
    : super(onEvent: event);
  @override
  Future<List<PtzProfile>> inspect({
    String? discoveredEndpoint,
    bool manualOnly = false,
  }) async => [
    PtzProfile(
      'profile',
      'Main',
      Uri.parse('http://192.168.1.100:5000/ptz'),
      VelocitySpace(generic, -1, 1, -1, 1, fraction: .1),
      null,
      capabilitySource: 'espaco_generico_declarado_no_perfil',
    ),
  ];
  @override
  Future<void> move(PtzProfile profile, int x, int y, int z) async {
    moves++;
  }

  @override
  Future<void> stop(PtzProfile profile) async {
    stops++;
  }
}

class ManualClient extends ProfileClient {
  final prepared = Completer<void>();
  int preparations = 0;
  bool holdEnabled = false;
  @override
  void setManualHold(PtzProfile profile, bool enabled) => holdEnabled = enabled;
  @override
  String? manualStopMethod(PtzProfile profile) =>
      'ContinuousMove_velocidade_zero';
  ManualClient(super.config, super.event);
  @override
  Future<List<PtzProfile>> inspect({
    String? discoveredEndpoint,
    bool manualOnly = false,
  }) async {
    manualCandidates.clear();
    manualCandidates.add(
      PtzProfile(
        'actual-profile',
        'Teste 1',
        Uri.parse('http://192.168.1.100:5000/ptz'),
        VelocitySpace('', -1, 1, -1, 1, fraction: .1),
        null,
        capabilitySource: 'compatibilidade_yoosee_manual',
      ),
    );
    return List.of(manualCandidates);
  }

  @override
  Future<void> prepareManual(
    PtzProfile profile, {
    bool? preferredMinimal,
    bool? preferredZeroStop,
  }) async {
    preparations++;
    await prepared.future;
  }
}

void main() {
  testWidgets(
    'Pressão renova movimento, soltar para e segundo plano desativa',
    (tester) async {
      late ManualClient client;
      Map<String, dynamic> report = {};
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CameraControls(
                config: const CameraConfig(),
                enabled: true,
                onReport: (r) => report = r,
                clientFactory: (config, event) =>
                    client = ManualClient(config, event),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Testar compatibilidade Yoosee'));
      await tester.pumpAndSettle();
      client.prepared.complete();
      await tester.ensureVisible(find.text('Ativar teste de movimento'));
      await tester.tap(find.text('Ativar teste de movimento'));
      await tester.pumpAndSettle();
      final toggle = find.byType(SwitchListTile);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(client.holdEnabled, true);
      final control = find.byType(HoldCameraButton).at(2);
      await tester.ensureVisible(control);
      final gesture = await tester.startGesture(tester.getCenter(control));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 450));
      expect(client.moves, 3);
      expect(client.stops, 0);
      await gesture.up();
      await tester.pump();
      expect(client.stops, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(client.moves, 3);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(toggle).value, false);
      expect(tester.widget<HoldCameraButton>(control).enabled, false);
      expect(report['resultado']['modoPressao'], false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final cancelBeforeReply in [false, true]) {
    testWidgets(
      'Teste Yoosee aguarda parada prévia e cancela ativação ao sair: $cancelBeforeReply',
      (tester) async {
        late ManualClient client;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: CameraControls(
                  config: const CameraConfig(),
                  enabled: true,
                  onReport: (_) {},
                  clientFactory: (config, event) =>
                      client = ManualClient(config, event),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Testar compatibilidade Yoosee'));
        await tester.pumpAndSettle();
        expect(client.moves, 0);
        final activate = find.text('Ativar teste de movimento');
        await tester.ensureVisible(activate);
        await tester.tap(activate);
        await tester.pump();
        expect(client.preparations, 1);
        expect(
          tester
              .widget<HoldCameraButton>(find.byType(HoldCameraButton).at(2))
              .enabled,
          false,
        );
        if (cancelBeforeReply) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        client.prepared.complete();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<HoldCameraButton>(find.byType(HoldCameraButton).at(2))
              .enabled,
          !cancelBeforeReply,
        );
        if (!cancelBeforeReply) {
          final control = find.byType(HoldCameraButton).at(2);
          await tester.ensureVisible(control);
          final gesture = await tester.startGesture(tester.getCenter(control));
          await tester.pump(const Duration(milliseconds: 700));
          await gesture.up();
          await tester.pump();
          expect(client.moves, 1);
          expect(client.stops, 1);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
          expect(
            tester
                .widget<HoldCameraButton>(find.byType(HoldCameraButton).at(2))
                .enabled,
            false,
          );
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Movimento do perfil de compatibilidade fica bloqueado até ativação manual',
    (tester) async {
      late ProfileClient client;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CameraControls(
                config: const CameraConfig(),
                enabled: true,
                onReport: (_) {},
                clientFactory: (config, event) =>
                    client = ProfileClient(config, event),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Verificar controles ONVIF'));
      await tester.pumpAndSettle();
      var button = tester.widget<HoldCameraButton>(
        find.byType(HoldCameraButton).at(2),
      );
      expect(button.enabled, false);
      expect(client.moves, 0);
      final activate = find.text('Ativar teste de movimento');
      await tester.ensureVisible(activate);
      await tester.tap(activate);
      await tester.pumpAndSettle();
      button = tester.widget<HoldCameraButton>(
        find.byType(HoldCameraButton).at(2),
      );
      expect(button.enabled, true);
      final control = find.byType(HoldCameraButton).at(2);
      await tester.ensureVisible(control);
      final gesture = await tester.startGesture(tester.getCenter(control));
      await tester.pump(const Duration(milliseconds: 150));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(client.moves, 1);
      expect(client.stops, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
