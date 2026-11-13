import 'camera.dart';

/// Conservative subset of mpv 0.36 low-latency settings. Keep the HEVC probe
/// that fixed missing VPS/SPS/PPS; never enable fflags=nobuffer here.
Map<String, String> playbackOptions(
  CameraConfig config,
  Transport transport,
) => {
  'rtsp-transport': transport.name,
  'network-timeout': '10',
  'demuxer-lavf-o':
      'timeout=10000000,allowed_media_types=video+audio,analyzeduration=10000000,probesize=10000000',
  'aid': 'no', // Muted audio must not remain the clock master.
  'cache': 'no',
  if (config.tuning == PlaybackTuning.responsive) ...{
    'demuxer-readahead-secs': '0',
    'audio-buffer': '0.1',
    'vd-lavc-threads': '1',
    'cache-pause': 'no',
    'video-sync': 'audio',
    'interpolation': 'no',
  },
  'msg-level': 'all=warn,ffmpeg=trace,lavf=debug,cplayer=info,vd=debug,vo=info',
};
