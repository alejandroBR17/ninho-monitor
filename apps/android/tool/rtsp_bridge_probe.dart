import 'dart:async';
import 'dart:io';
import 'package:media_kit/media_kit.dart';
import 'package:jortan_viewer/camera.dart';
import 'package:jortan_viewer/rtsp_bridge.dart';
import 'package:jortan_viewer/playback_options.dart';

Future<void> main(List<String> args) async {
  MediaKit.ensureInitialized(libmpv: args[0]);
  final port = int.parse(args[1]);
  final config = CameraConfig(
    host: '127.0.0.1',
    port: port,
    username: 'viewer',
    password: 'test-only',
    path: args.contains('--fluid') ? '/onvif2' : '/onvif1',
    tuning: args.contains('--fluid')
        ? PlaybackTuning.responsive
        : PlaybackTuning.compatible,
  );
  Map<String, dynamic> status = {};
  final bridge = RtspCompatibilityBridge(
    config: config,
    onStatus: (value) => status = value,
  );
  await bridge.start();
  final player = Player(
    configuration: const PlayerConfiguration(vo: 'null', muted: true),
  );
  final errors = <String>[];
  final subscription = player.stream.error.listen(
    (message) => errors.add(message),
  );
  try {
    final native = player.platform as NativePlayer;
    for (final option in playbackOptions(config, Transport.tcp).entries) {
      await native.setProperty(option.key, option.value);
    }
    await native.setProperty('ao', 'null');
    await native.setProperty('vid', 'auto');
    final decoded = player.stream.position.firstWhere(
      (time) => time > const Duration(milliseconds: 150),
    );
    final videoParameters = player.stream.videoParams.firstWhere(
      (params) => (params.w ?? 0) > 0 && (params.h ?? 0) > 0,
    );
    await player.open(Media(bridge.uri.toString()));
    await Future.wait([
      decoded,
      videoParameters,
    ]).timeout(const Duration(seconds: 15));
    if ((player.state.videoParams.w ?? 0) == 0) {
      throw StateError('Nenhum vídeo decodificado.');
    }
    if (await native.getProperty('aid') != 'no') {
      throw StateError('Áudio não iniciou desativado.');
    }
    if (args.contains('--expect-audio')) {
      final decodedAudio = player.stream.audioParams
          .firstWhere((p) => (p.sampleRate ?? 0) > 0)
          .timeout(const Duration(seconds: 8));
      await native.setProperty('aid', 'auto');
      await player.setVolume(100);
      await decodedAudio;
      if (double.tryParse(await native.getProperty('volume')) != 100) {
        throw StateError('Não ativou a escuta.');
      }
      stdout.writeln(
        'Áudio decodificado: ${player.state.audioParams.sampleRate} Hz; início com aid=no e ativação conferidos.',
      );
      await player.setVolume(0);
      await native.setProperty('aid', 'no');
      if (await native.getProperty('aid') != 'no' ||
          double.tryParse(await native.getProperty('volume')) != 0) {
        throw StateError('Não desativou a faixa de áudio.');
      }
    }
    if (args.contains('--expect-frame')) {
      final image = await player.screenshot(format: 'image/png');
      if (image == null ||
          image.length < 8 ||
          image[0] != 137 ||
          image[1] != 80) {
        throw StateError('O motor não entregou uma captura PNG.');
      }
      stdout.writeln('Captura PNG entregue pelo motor: ${image.length} bytes.');
    }
    final fixes = (status['correcoesTransporte'] as List).length;
    if (port == 8854 && fixes == 0) {
      throw StateError('A simulação não exigiu a correção esperada.');
    }
    if ((status['pacotesIntercalados'] as int) == 0) {
      throw StateError('Nenhum RTP intercalado recebido.');
    }
    stdout.writeln(
      'Vídeo ${player.state.videoParams.w}x${player.state.videoParams.h}; correções: $fixes; RTP: ${status['pacotesIntercalados']}.',
    );
  } catch (error) {
    final scrub = Redactor()..add(config);
    stderr.writeln(
      scrub.clean('Falha: $error; estado: $status; erros: $errors'),
    );
    exitCode = 1;
  } finally {
    await player.dispose();
    await bridge.close();
    await subscription.cancel();
  }
}
