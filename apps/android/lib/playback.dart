import 'package:media_kit_video/media_kit_video.dart';
import 'dart:typed_data';
import 'camera.dart';

enum PlaybackEventKind { log, failure, progress, diagnostic }

class PlaybackEvent {
  final PlaybackEventKind kind;
  final String message;
  final Map<String, dynamic>? data;
  const PlaybackEvent(this.kind, [this.message = '', this.data]);
}

abstract class PlaybackSession {
  VideoController? get video;
  Future<void> get firstFrame;
  Stream<PlaybackEvent> get events;
  Future<void> open(CameraConfig config, Transport transport);
  Future<void> close();
}

typedef SessionFactory = PlaybackSession Function();

abstract interface class AudioPlaybackSession {
  Future<void> setAudioEnabled(bool enabled);
}

abstract interface class CapturePlaybackSession {
  Future<Uint8List?> captureFrame();
}
