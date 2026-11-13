import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/camera_controls.dart';

void main() {
  testWidgets('Seta para ao soltar, cancelar gesto ou perder habilitação', (
    tester,
  ) async {
    var starts = 0, stops = 0;
    Widget button(bool enabled) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: HoldCameraButton(
            label: 'Girar',
            icon: Icons.arrow_left,
            enabled: enabled,
            onStart: () => starts++,
            onStop: () => stops++,
          ),
        ),
      ),
    );
    await tester.pumpWidget(button(true));
    var gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldCameraButton)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(starts, 1);
    await gesture.up();
    await tester.pump();
    expect(stops, 1);
    gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldCameraButton)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.cancel();
    await tester.pump();
    expect(stops, 2);
    gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldCameraButton)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpWidget(button(false));
    expect(stops, 3);
    await gesture.up();
    await tester.pump();
    expect(stops, 3);
    await tester.tap(find.byType(HoldCameraButton));
    await tester.pump();
    expect(starts, 3);
    expect(tester.takeException(), isNull);
  });
}
