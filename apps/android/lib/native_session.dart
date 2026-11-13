import 'dart:async';
import 'dart:typed_data';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'camera.dart';
import 'playback.dart';
import 'rtsp_probe.dart';
import 'rtsp_bridge.dart';
import 'playback_options.dart';

class NativeSession
    implements PlaybackSession, AudioPlaybackSession, CapturePlaybackSession {
  static final _characterDump = RegExp(r'rtsp: ret=-?\d+ c=');
  final Player _player = Player(
    configuration: const PlayerConfiguration(
      title: 'Jortan Viewer',
      muted: true,
      logLevel: MPVLogLevel.trace,
      bufferSize: 4 * 1024 * 1024,
    ),
  );
  late final VideoController _video = VideoController(_player);
  final _events = StreamController<PlaybackEvent>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final RtspProbe _probe = RtspProbe();
  RtspCompatibilityBridge? _bridge;
  bool _closed = false, _liveLogs = false;
  Future<void>? _closing;
  NativeSession() {
    // Attach video before opening the native player.
    _video;
    _subscriptions.add(
      _player.stream.log.listen((log) {
        if (_characterDump.hasMatch(log.text) || log.text.trim() == ']') {
          return;
        }
        if (_liveLogs &&
            !['error', 'fatal', 'warn', 'warning'].contains(log.level)) {
          return;
        }
        _emit(
          PlaybackEvent(
            PlaybackEventKind.log,
            '${log.level} [${log.prefix}]: ${log.text}',
          ),
        );
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((message) {
        if (!isTerminalPlayerError(message)) {
          _emit(
            PlaybackEvent(PlaybackEventKind.diagnostic, 'aviso_do_motor', {
              'mensagem': message,
              'fatal': false,
            }),
          );
        } else {
          _emit(PlaybackEvent(PlaybackEventKind.failure, message));
        }
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((completed) {
        if (completed) {
          _emit(
            const PlaybackEvent(
              PlaybackEventKind.failure,
              'O fluxo foi encerrado pela câmera.',
            ),
          );
        }
      }),
    );
    _subscriptions.add(
      _player.stream.videoParams.listen((params) {
        if (params.w != null && params.w! > 0) {
          _emit(
            PlaybackEvent(PlaybackEventKind.diagnostic, 'parametros_video', {
              'largura': params.w,
              'altura': params.h,
              'formatoPixel': params.pixelformat,
            }),
          );
        }
      }),
    );
    _subscriptions.add(
      _player.stream.tracks.listen((tracks) {
        bool real(String id) => id != 'auto' && id != 'no';
        // Initial track lists contain only pseudo selections; they do not
        // establish that the stream lacks audio, especially on UDP fallback.
        if (!tracks.video.any((track) => real(track.id))) return;
        _emit(
          PlaybackEvent(PlaybackEventKind.diagnostic, 'disponibilidade_audio', {
            'disponivel': tracks.audio.any((track) => real(track.id)),
            'origem': 'faixas_identificadas_pelo_motor',
            'observacao':
                'Faixa anunciada não comprova som audível nem sincronização.',
          }),
        );
      }),
    );
    _subscriptions.add(
      _player.stream.audioParams.listen((params) {
        if (params.sampleRate != null) {
          _emit(
            PlaybackEvent(PlaybackEventKind.diagnostic, 'parametros_audio', {
              'taxaAmostragem': params.sampleRate,
              'canais': params.channelCount,
              'formato': params.format,
            }),
          );
        }
      }),
    );
    Duration? lastPosition;
    _subscriptions.add(
      _player.stream.position.listen((position) {
        if (position != lastPosition) {
          lastPosition = position;
          _emit(const PlaybackEvent(PlaybackEventKind.progress));
        }
      }),
    );
  }
  void _emit(PlaybackEvent event) {
    if (!_closed) _events.add(event);
  }

  @override
  Future<Uint8List?> captureFrame() => _player.screenshot(format: 'image/png');

  @override
  VideoController get video => _video;
  @override
  Future<void> get firstFrame => _video.waitUntilFirstFrameRendered.then((_) {
    unawaited(_reduceLogging());
  });

  Future<void> _reduceLogging() async {
    if (_closed) return;
    _liveLogs = true;
    try {
      await (_player.platform as NativePlayer).setProperty(
        'msg-level',
        'all=warn,ffmpeg=warn,lavf=info,cplayer=info,vd=warn,vo=warn',
      );
      _emit(
        const PlaybackEvent(PlaybackEventKind.diagnostic, 'registro_ao_vivo', {
          'modo':
              'avisos_e_erros; negociação detalhada, sem dump caractere a caractere',
        }),
      );
    } catch (error) {
      _emit(
        PlaybackEvent(PlaybackEventKind.diagnostic, 'aviso_do_motor', {
          'mensagem': error.toString(),
          'fatal': false,
        }),
      );
    }
  }

  @override
  Stream<PlaybackEvent> get events => _events.stream;
  @override
  Future<void> open(CameraConfig config, Transport transport) async {
    if (transport == Transport.udp && config.transport == Transport.automatic) {
      _emit(
        const PlaybackEvent(PlaybackEventKind.diagnostic, 'teste_rtsp', {
          'omitido': true,
          'motivo':
              'O canal de controle TCP já foi testado na tentativa anterior; evitando conexões extras à câmera.',
        }),
      );
    } else {
      _emit(
        const PlaybackEvent(
          PlaybackEventKind.diagnostic,
          'teste_rtsp_iniciado',
        ),
      );
      final probe = await _probe.run(config);
      _emit(PlaybackEvent(PlaybackEventKind.diagnostic, 'teste_rtsp', probe));
    }
    if (_closed) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (_closed) return;
    final native = _player.platform as NativePlayer;
    final options = playbackOptions(config, transport);
    final applied = <String, dynamic>{};
    for (final entry in options.entries) {
      if (_closed) return;
      await native.setProperty(entry.key, entry.value);
      try {
        applied[entry.key] = {
          'solicitado': entry.value,
          'efetivo': await native.getProperty(entry.key),
        };
      } catch (error) {
        applied[entry.key] = {
          'solicitado': entry.value,
          'verificacao': error.toString(),
        };
      }
    }
    final versions = <String, dynamic>{};
    for (final key in ['mpv-version', 'ffmpeg-version']) {
      try {
        versions[key] = await native.getProperty(key);
      } catch (_) {
        versions[key] = 'indisponivel';
      }
    }
    _emit(
      PlaybackEvent(PlaybackEventKind.diagnostic, 'motor_configurado', {
        'versoes': versions,
        'opcoes': applied,
      }),
    );
    if (_closed) return;
    _emit(
      const PlaybackEvent(
        PlaybackEventKind.diagnostic,
        'abertura_rtsp_no_motor',
      ),
    );
    var mediaUri = config.uri;
    if (transport == Transport.tcp) {
      final bridge = RtspCompatibilityBridge(
        config: config,
        onStatus: (data) {
          _emit(
            PlaybackEvent(
              PlaybackEventKind.diagnostic,
              'compatibilidade_tcp',
              data,
            ),
          );
        },
      );
      _bridge = bridge;
      await bridge.start();
      if (_closed) {
        await bridge.close();
        return;
      }
      mediaUri = bridge.uri;
    }
    await _player.open(Media(mediaUri.toString()));
  }

  @override
  Future<void> setAudioEnabled(bool enabled) async {
    if (_closed) return;
    final native = _player.platform as NativePlayer;
    if (!enabled) await _player.setVolume(0);
    try {
      await native.setProperty('aid', enabled ? 'auto' : 'no');
      if (enabled) await _player.setVolume(100);
    } catch (_) {
      // Restore silence and the video-only clock if audio activation fails.
      if (enabled && !_closed) {
        try {
          await _player.setVolume(0);
          await native.setProperty('aid', 'no');
        } catch (_) {}
      }
      rethrow;
    }
    _emit(
      PlaybackEvent(PlaybackEventKind.diagnostic, 'audio', {
        'escutaSolicitada': enabled,
        'volume': enabled ? 100 : 0,
        'faixaAudioSolicitada': enabled ? 'auto' : 'no',
        'observacao': 'Volume liberado não comprova que a câmera enviou áudio.',
      }),
    );
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _probe.cancel();
    await _bridge?.close();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    await _events.close();
  }
}
