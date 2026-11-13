import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/connection.dart';
import 'package:jortan_viewer/design.dart';
import 'package:jortan_viewer/session_overview.dart';
import 'connection_test.dart' show FakeSession;

void main() {
  testWidgets(
    'Resumo distingue vídeo, áudio ausente e teste manual em tela estreita',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final connection = CameraConnection(factory: () => FakeSession());
      connection.phase = ConnectionPhase.live;
      connection.audioAvailable = false;
      connection.attempts.add(
        Attempt('tcp', 0)
          ..checks['parametros_video'] = {'largura': 640, 'altura': 360},
      );
      connection.controlsReport = {
        'resultado': {
          'modo': 'compatibilidade_yoosee_manual',
          'testeAtivo': false,
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: SingleChildScrollView(
                child: SessionOverview(connection: connection),
              ),
            ),
          ),
        ),
      );
      expect(find.text('640 × 360 · TCP'), findsOneWidget);
      expect(find.text('Este fluxo não anunciou áudio.'), findsOneWidget);
      expect(find.text('Teste manual aguardando ativação'), findsOneWidget);
      expect(find.textContaining('Movimento confirmado'), findsNothing);
      expect(tester.takeException(), isNull);
      connection.dispose();
    },
  );
}
