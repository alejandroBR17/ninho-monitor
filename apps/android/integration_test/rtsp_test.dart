import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/connection.dart';
import 'package:jortan_viewer/native_session.dart';

// Only synthetic fixture credentials. Never put real camera passwords here.
const fixtureHost = String.fromEnvironment(
  'RTSP_HOST',
  defaultValue: '10.0.2.2',
);
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  for (final transport in [Transport.tcp, Transport.udp]) {
    testWidgets('RTSP ${transport.name}: primeiro quadro renderizado', (
      tester,
    ) async {
      final connection = CameraConnection(factory: NativeSession.new);
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedBuilder(
            animation: connection,
            builder: (context, _) {
              final video = connection.session?.video;
              return Scaffold(
                body: video == null
                    ? const SizedBox()
                    : Video(controller: video),
              );
            },
          ),
        ),
      );
      await connection.connect(
        CameraConfig(
          host: fixtureHost,
          port: 8554,
          username: 'viewer',
          password: 'test-only',
          transport: transport,
        ),
      );
      for (
        var i = 0;
        i < 220 &&
            connection.phase != ConnectionPhase.live &&
            connection.phase != ConnectionPhase.failed;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final received = connection.phase == ConnectionPhase.live;
      await connection.disconnect();
      final report = connection.report();
      connection.dispose();
      expect(received, isTrue, reason: report);
    });
  }
  for (final invalidPath in [false, true]) {
    testWidgets(
      invalidPath ? 'RTSP: caminho inexistente' : 'RTSP: senha recusada',
      (tester) async {
        final connection = CameraConnection(factory: NativeSession.new);
        await tester.pumpWidget(
          MaterialApp(
            home: AnimatedBuilder(
              animation: connection,
              builder: (context, _) {
                final video = connection.session?.video;
                return Scaffold(
                  body: video == null
                      ? const SizedBox()
                      : Video(controller: video),
                );
              },
            ),
          ),
        );
        await connection.connect(
          CameraConfig(
            host: fixtureHost,
            port: 8554,
            username: 'viewer',
            password: invalidPath ? 'test-only' : 'wrong-password',
            path: invalidPath ? '/missing' : '/onvif1',
            transport: Transport.tcp,
          ),
        );
        for (
          var i = 0;
          i < 220 && connection.phase != ConnectionPhase.failed;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final failed = connection.phase == ConnectionPhase.failed;
        final frames = connection.attempts.any((a) => a.videoReceived);
        await connection.disconnect();
        connection.dispose();
        expect(failed, isTrue);
        expect(frames, isFalse);
      },
    );
  }
}
