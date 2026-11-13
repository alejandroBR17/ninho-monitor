// Linux-only development probe against scripts/rtsp_fixture.py.
// This verifies the native media_kit/libmpv RTSP pipeline, not mobile rendering.
import 'dart:async';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:jortan_viewer/rtsp_probe.dart';
import 'package:jortan_viewer/camera.dart';

Future<void> main(List<String> args) async {
  MediaKit.ensureInitialized(libmpv: args.single);
  final check = await RtspProbe().run(
    const CameraConfig(
      host: '127.0.0.1',
      port: 8554,
      username: 'viewer',
      password: 'test-only',
    ),
  );
  if (check['statusDescribe'] != 200 ||
      (check['sdp'] as Map?)?['videoAnunciado'] != true) {
    throw StateError('O teste direto não recebeu SDP de vídeo: $check');
  }
  stdout.writeln('Teste direto RTSP autenticado e SDP: conferidos.');
  for (final transport in ['tcp', 'udp']) {
    final player = Player(
      configuration: const PlayerConfiguration(vo: 'null', muted: true),
    );
    try {
      final native = player.platform as NativePlayer;
      await native.setProperty('rtsp-transport', transport);
      await native.setProperty('network-timeout', '10');
      await native.setProperty(
        'demuxer-lavf-o',
        'timeout=10000000,allowed_media_types=video',
      );
      await native.setProperty('aid', 'no');
      await native.setProperty('vid', 'auto');
      await native.setProperty('cache', 'no');
      final decoded = player.stream.position.firstWhere(
        (time) => time > const Duration(milliseconds: 150),
      );
      await player.open(Media('rtsp://viewer:test-only@127.0.0.1:8554/onvif1'));
      await decoded.timeout(const Duration(seconds: 15));
      final params = player.state.videoParams;
      if (params.w == null || params.w! <= 0) {
        throw StateError('Sem vídeo decodificado.');
      }
      stdout.writeln(
        '$transport: vídeo ${params.w}x${params.h}, reprodução avançando',
      );
    } finally {
      await player.dispose();
    }
  }
}
