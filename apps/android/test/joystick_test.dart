import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera_joystick.dart';
import 'package:jortan_viewer/design.dart';

void main() {
  testWidgets(
    'Arrastar joystick não rola a página, inclusive com texto ampliado',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scroll = ScrollController();
      final directions = <(int, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: ListView(
                controller: scroll,
                children: [
                  CameraJoystick(
                    enabled: true,
                    onDirection: (x, y) => directions.add((x, y)),
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(CameraJoystick));
      final gesture = await tester.startGesture(center);
      await gesture.moveTo(center + const Offset(0, -64));
      await tester.pump();
      expect(directions.last, (0, 1));
      expect(scroll.offset, 0);
      await gesture.up();
      await tester.pump();
      expect(directions.last, (0, 0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );

  for (final finish in ['soltar', 'cancelar', 'desabilitar', 'parar']) {
    testWidgets('Joystick move, volta ao centro e para ao $finish', (
      tester,
    ) async {
      final directions = <(int, int)>[];
      Widget screen({bool enabled = true, int revision = 0}) => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: CameraJoystick(
              enabled: enabled,
              stopRevision: revision,
              onDirection: (x, y) => directions.add((x, y)),
            ),
          ),
        ),
      );
      await tester.pumpWidget(screen());
      final center = tester.getCenter(
        find.byKey(const ValueKey('camera-joystick')),
      );
      final gesture = await tester.startGesture(center);
      await gesture.moveTo(center + const Offset(64, 0));
      await tester.pump();
      expect(directions.last, (1, 0));
      final count = directions.length;
      await gesture.moveTo(center + const Offset(72, 0));
      await tester.pump();
      expect(directions.length, count); // Same sector never floods commands.
      await gesture.moveTo(center);
      await tester.pump();
      expect(directions.last, (0, 0));
      await gesture.moveTo(center + const Offset(0, -64));
      await tester.pump();
      expect(directions.last, (0, 1));
      switch (finish) {
        case 'soltar':
          await gesture.up();
        case 'cancelar':
          await gesture.cancel();
        case 'desabilitar':
          await tester.pumpWidget(screen(enabled: false));
          await gesture.up();
        case 'parar':
          await tester.pumpWidget(screen(revision: 1));
          final afterStop = directions.length;
          await gesture.moveTo(center + const Offset(64, 0));
          await tester.pump();
          expect(directions.length, afterStop);
          await gesture.up();
      }
      await tester.pump();
      expect(directions.last, (0, 0));
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'Centro não move, limite impede reinício até soltar e remoção para',
    (tester) async {
      final directions = <(int, int)>[];
      Widget screen() => MaterialApp(
        home: Scaffold(
          body: Center(
            child: CameraJoystick(
              enabled: true,
              onDirection: (x, y) => directions.add((x, y)),
            ),
          ),
        ),
      );
      await tester.pumpWidget(screen());
      final center = tester.getCenter(find.byType(CameraJoystick));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(directions, isEmpty);
      await gesture.moveTo(center + const Offset(64, -64));
      await tester.pump();
      expect(directions.last, (1, 1));
      await tester.pump(const Duration(seconds: 5));
      expect(directions.last, (0, 0));
      final expiredCount = directions.length;
      await gesture.moveTo(center + const Offset(-64, 0));
      await tester.pump();
      expect(directions.length, expiredCount);
      await gesture.up();
      await tester.pump();
      final next = await tester.startGesture(center);
      await next.moveTo(center + const Offset(-64, 0));
      await tester.pump();
      expect(directions.last, (-1, 0));
      await tester.pumpWidget(const SizedBox());
      expect(directions.last, (0, 0));
      await next.up();
    },
  );
}
