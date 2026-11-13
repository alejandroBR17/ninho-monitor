import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jortan_viewer/video_actions.dart';

void main() {
  testWidgets(
    'Tela cheia tem entrada e saída; redefinir zoom é ação distinta',
    (tester) async {
      final zoom = TransformationController();
      var fullscreen = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => Column(
                children: [
                  VideoFullscreenButton(
                    fullscreen: fullscreen,
                    onToggle: () => update(() => fullscreen = !fullscreen),
                  ),
                  ImageZoomReset(controller: zoom),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.byTooltip('Tela cheia'), findsOneWidget);
      expect(find.byIcon(Icons.zoom_out_map), findsNothing);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Tela cheia'));
      await tester.pump();
      expect(fullscreen, true);
      expect(find.byTooltip('Sair da tela cheia'), findsOneWidget);
      await tester.tap(find.byTooltip('Sair da tela cheia'));
      await tester.pump();
      expect(fullscreen, false);
      zoom.value = Matrix4.diagonal3Values(2, 2, 1);
      await tester.pump();
      await tester.tap(find.text('Redefinir zoom'));
      await tester.pump();
      expect(zoom.value.isIdentity(), true);
      expect(fullscreen, false);
      await tester.pumpWidget(const SizedBox());
      zoom.dispose();
    },
  );
}
