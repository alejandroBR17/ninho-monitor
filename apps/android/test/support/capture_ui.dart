// Optional headless UI capture: FLUTTER_ROOT=/path/to/flutter flutter test test/support/capture_ui.dart
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jortan_viewer/app.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/viewing_controls.dart';
import 'package:jortan_viewer/daily_camera_controls.dart';
import 'package:jortan_viewer/design.dart';
import '../daily_controls_test.dart' show DailyClient, MemoryControlStore;

void main() {
  testWidgets('Capture interface sem câmera ou senha', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final flutter = Platform.environment['FLUTTER_ROOT'];
    if (flutter != null) {
      await tester.runAsync(() async {
        final loader = FontLoader('Roboto');
        loader.addFont(
          File(
            '$flutter/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf',
          ).readAsBytes().then(ByteData.sublistView),
        );
        await loader.load();
        final icons = FontLoader('MaterialIcons');
        icons.addFont(
          File(
            '$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then(ByteData.sublistView),
        );
        await icons.load();
      });
    }
    FlutterSecureStorage.setMockInitialValues({});
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const JortanApp()),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String file) async {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(file).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('docs/preview-home.png');
    await tester.tap(find.text('Remoto'));
    await tester.pumpAndSettle();
    await capture('docs/preview-remote.png');
    await tester.tap(find.text('Ao vivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configurar minha câmera'));
    await tester.pumpAndSettle();
    await capture('docs/preview-config.png');
    await tester.pumpWidget(const SizedBox());
    FlutterSecureStorage.setMockInitialValues({
      'camera.v1': jsonEncode(const CameraConfig().toJson()),
    });
    await tester.pumpWidget(
      RepaintBoundary(key: key, child: const JortanApp()),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Imagem e som'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Imagem e som'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(ViewingControls),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await capture('docs/preview-viewing.png');

    await tester.pumpWidget(const SizedBox());
    late DailyClient dailyClient;
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          home: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: DailyCameraControls(
                  config: const CameraConfig(),
                  enabled: true,
                  store: MemoryControlStore(),
                  onReport: (_) {},
                  clientFactory: (config, event) =>
                      dailyClient = DailyClient(config, event),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(dailyClient.moves, 0);
    await capture('docs/preview-control.png');
    await tester.tap(find.text('Joystick'));
    await tester.pumpAndSettle();
    await capture('docs/preview-joystick.png');
    expect(tester.takeException(), isNull);
  });
}
