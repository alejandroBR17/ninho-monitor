import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'camera.dart';
import 'playback.dart';
import 'version.dart';

enum ConnectionPhase { idle, connecting, live, reconnecting, failed }

class _Cancelled implements Exception {}

class CameraConnection extends ChangeNotifier {
  final SessionFactory factory;
  final Duration frameTimeout, stallTimeout, transportCooldown;
  final List<Duration> retryDelays;
  CameraConnection({
    required this.factory,
    this.transportCooldown = const Duration(seconds: 1),
    this.frameTimeout = const Duration(seconds: 15),
    this.stallTimeout = const Duration(seconds: 20),
    this.retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
    ],
  });
  CameraConfig config = const CameraConfig();
  ConnectionPhase phase = ConnectionPhase.idle;
  String message = 'Sua câmera, direto no celular.';
  final List<Attempt> attempts = [];
  final Redactor redactor = Redactor();
  final List<Map<String, dynamic>> appErrors = [];
  Map<String, dynamic>? discoveryReport;
  Map<String, dynamic>? controlsReport;
  bool audioEnabled = false, audioChanging = false;
  bool? audioAvailable;
  String? audioError;
  Future<Uint8List> captureFrame() async {
    final current = session;
    if (phase != ConnectionPhase.live || current is! CapturePlaybackSession) {
      throw StateError('Conecte o vídeo antes de capturar uma imagem.');
    }
    final bytes = await (current as CapturePlaybackSession).captureFrame();
    if (!identical(current, session) || phase != ConnectionPhase.live) {
      throw StateError('A transmissão mudou durante a captura.');
    }
    if (bytes == null || bytes.isEmpty || bytes.length > 32 * 1024 * 1024) {
      throw StateError('O reprodutor não entregou uma imagem válida.');
    }
    return bytes;
  }

  Future<void> toggleAudio() async {
    final current = session;
    if (phase != ConnectionPhase.live ||
        current is! AudioPlaybackSession ||
        audioChanging ||
        (audioAvailable == false && !audioEnabled)) {
      return;
    }
    audioChanging = true;
    audioError = null;
    _notify();
    final enabled = !audioEnabled;
    try {
      await (current as AudioPlaybackSession).setAudioEnabled(enabled);
      if (identical(current, session)) audioEnabled = enabled;
    } catch (error, stack) {
      recordAppError('alternar_audio', error, stack);
      audioError = 'Não foi possível alterar o áudio. Consulte o diagnóstico.';
    } finally {
      audioChanging = false;
      _notify();
    }
  }

  bool get hasDiagnostics =>
      attempts.isNotEmpty ||
      appErrors.isNotEmpty ||
      discoveryReport != null ||
      controlsReport != null;
  void recordAppError(
    String stage,
    Object error,
    StackTrace stack, {
    bool sensitive = false,
  }) {
    if (appErrors.length >= 30) appErrors.removeAt(0);
    appErrors.add({
      'horario': DateTime.now().toUtc().toIso8601String(),
      'etapa': stage,
      'tipo': error.runtimeType.toString(),
      'mensagem': sensitive
          ? 'Detalhes de armazenamento omitidos para proteger credenciais.'
          : redactor.clean(error.toString()),
      'stack': redactor.clean(stack.toString()).split('\n').take(14).toList(),
    });
  }

  PlaybackSession? session;
  bool _disposed = false;
  int _generation = 0;
  Completer<void> _cancel = Completer<void>();
  Future<void>? _running;
  bool get active =>
      phase == ConnectionPhase.connecting ||
      phase == ConnectionPhase.live ||
      phase == ConnectionPhase.reconnecting;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> connect(CameraConfig value) async {
    final stopping = disconnect();
    final expectedGeneration = _generation;
    await stopping;
    if (_disposed || _generation != expectedGeneration) return;
    config = value;
    redactor.add(value);
    final invalid = value.validate();
    if (invalid != null) {
      phase = ConnectionPhase.failed;
      message = invalid;
      _notify();
      return;
    }
    attempts.clear();
    _cancel = Completer<void>();
    final generation = ++_generation;
    _running = _run(generation, _cancel.future);
    // This method launches the connection. Disconnection awaits its cleanup.
    unawaited(_running);
  }

  bool _current(int generation) => generation == _generation && !_disposed;
  Future<T> _interruptible<T>(Future<T> work, Future<void> cancelled) =>
      Future.any([work, cancelled.then<T>((_) => throw _Cancelled())]);

  Future<void> _run(int generation, Future<void> cancelled) async {
    try {
      for (var round = 0; round <= retryDelays.length; round++) {
        if (!_current(generation)) return;
        if (round > 0) {
          phase = ConnectionPhase.reconnecting;
          message = 'Reconectando • tentativa $round de ${retryDelays.length}';
          _notify();
          await _interruptible(
            Future<void>.delayed(retryDelays[round - 1]),
            cancelled,
          );
        }
        var receivedInRound = false;
        for (final transport in config.attempts) {
          if (!_current(generation)) return;
          if (transport == Transport.udp &&
              config.transport == Transport.automatic) {
            await _interruptible(
              Future<void>.delayed(transportCooldown),
              cancelled,
            );
            if (!_current(generation)) return;
          }
          phase = ConnectionPhase.connecting;
          message = 'Buscando vídeo por ${transport.name.toUpperCase()}…';
          final attempt = Attempt(transport.name, round);
          attempts.add(attempt);
          // Bound retained data across reconnect cycles.
          if (attempts.length > 12) attempts.removeAt(0);
          final failed = Completer<String>();
          Timer? watchdog;
          StreamSubscription<PlaybackEvent>? subscription;
          PlaybackSession? current;
          try {
            current = factory();
            session = current;
            audioEnabled = false;
            audioAvailable = null;
            audioError = null;
            subscription = current.events.listen((event) {
              if (!_current(generation)) return;
              switch (event.kind) {
                case PlaybackEventKind.log:
                  attempt.addLog(redactor.clean(event.message));
                case PlaybackEventKind.diagnostic:
                  final safe = _safe(event.data ?? const {}) as Map;
                  attempt.checks[event.message] = safe;
                  attempt.event(event.message);
                  if (event.message == 'teste_rtsp') {
                    final sdp = safe['sdp'];
                    if (sdp is Map &&
                        sdp['presente'] == true &&
                        sdp['audioAnunciado'] is bool) {
                      audioAvailable = sdp['audioAnunciado'] as bool;
                    }
                    final replies = (safe['respostas'] as List? ?? const [])
                        .where((reply) => reply['metodo'] == 'DESCRIBE')
                        .toList();
                    if (replies.isNotEmpty) {
                      final reply = replies.last;
                      attempt.addLog(
                        'Teste direto DESCRIBE final: RTSP/1.0 ${reply['status']} '
                        '(autenticado: ${reply['autenticado']}, CSeq confere: ${reply['cseqConfere']})',
                      );
                    }
                    if (safe['autenticacaoConfirmada'] == true) {
                      attempt.addLog('Teste direto: autenticacao confirmada.');
                    }
                  }
                  if (event.message == 'parametros_audio' &&
                      audioAvailable != true) {
                    audioAvailable = true;
                    _notify();
                  }
                  if (event.message == 'disponibilidade_audio') {
                    final available = safe['disponivel'] as bool?;
                    if (available != audioAvailable) {
                      audioAvailable = available;
                      _notify();
                    }
                  }
                case PlaybackEventKind.failure:
                  if (!failed.isCompleted) {
                    failed.complete(redactor.clean(event.message));
                  }
                case PlaybackEventKind.progress:
                  if (attempt.videoReceived) {
                    watchdog?.cancel();
                    watchdog = Timer(stallTimeout, () {
                      if (!failed.isCompleted) {
                        failed.complete('O vídeo parou de avançar.');
                      }
                    });
                  }
              }
            });
            _notify();
            // Register failure handling before opening: native errors can arrive immediately.
            final failure = failed.future.then<void>(
              (text) => throw StateError(text),
            );
            await _interruptible(
              Future.any([current.open(config, transport), failure]).timeout(
                const Duration(seconds: 24),
                onTimeout: () => throw TimeoutException(
                  'A preparação do motor/negociação RTSP não terminou em 24 segundos.',
                ),
              ),
              cancelled,
            );
            attempt.event('aguardando_primeiro_quadro');
            await _interruptible(
              Future.any([current.firstFrame, failure]).timeout(
                frameTimeout,
                onTimeout: () => throw TimeoutException(
                  'Nenhum quadro de vídeo chegou em ${frameTimeout.inSeconds} segundos após iniciar o motor.',
                ),
              ),
              cancelled,
            );
            if (!_current(generation)) throw _Cancelled();
            attempt.videoReceived = true;
            attempt.result = 'Recebendo vídeo';
            attempt.event('primeiro_quadro_renderizado');
            receivedInRound = true;
            phase = ConnectionPhase.live;
            message = 'Ao vivo • ${transport.name.toUpperCase()}';
            watchdog = Timer(stallTimeout, () {
              if (!failed.isCompleted) {
                failed.complete('O vídeo parou de avançar.');
              }
            });
            _notify();
            // The live session remains here until loss or explicit cancellation.
            final reason = await _interruptible(failed.future, cancelled);
            throw StateError(reason);
          } on _Cancelled {
            attempt.result = 'Interrompida pelo aplicativo';
            rethrow;
          } catch (error, stack) {
            attempt.checks['excecao'] = {
              'tipo': error.runtimeType.toString(),
              'stack': redactor
                  .clean(stack.toString())
                  .split('\n')
                  .take(18)
                  .toList(),
            };
            attempt.result = redactor.clean(error.toString());
            attempt.finding = diagnoseFailure(
              '${attempt.result}\n${attempt.logs.join('\n')}',
              finalRtspStatus: attempt.lastRtspStatus,
            );
            attempt.event('falha', {'tipo': error.runtimeType.toString()});
            message = attempt.finding!.message;
          } finally {
            attempt.ended = DateTime.now().toUtc();
            watchdog?.cancel();
            await subscription?.cancel();
            if (identical(session, current)) session = null;
            if (current != null) {
              try {
                await current.close();
              } catch (error) {
                attempt.checks['erroEncerramento'] = redactor.clean(
                  error.toString(),
                );
              }
            }
          }
          if (!_current(generation)) return;
          // After a previously live stream drops, start a reconnect round.
          if (receivedInRound) break;
        }
        // Initial connection failures are reported immediately after transport fallback.
        if (round == 0 && !receivedInRound) break;
      }
      if (_current(generation)) {
        phase = ConnectionPhase.failed;
        _notify();
      }
    } on _Cancelled {
      // The caller owns the new visible state.
    } catch (error) {
      if (_current(generation)) {
        phase = ConnectionPhase.failed;
        message = redactor.clean(
          'Não foi possível iniciar o reprodutor: $error',
        );
        _notify();
      }
    }
  }

  Future<void> disconnect({String? reason}) async {
    ++_generation;
    if (!_cancel.isCompleted) _cancel.complete();
    final running = _running;
    _running = null;
    session = null;
    audioEnabled = false;
    audioAvailable = null;
    phase = ConnectionPhase.idle;
    message = reason ?? 'Conexão encerrada. Toque em conectar para assistir.';
    _notify();
    await running;
  }

  Object? _safe(Object? value) {
    if (value is String) return redactor.clean(value);
    if (value is List) return value.map(_safe).toList();
    if (value is Map) {
      return value.map((key, value) => MapEntry(key, _safe(value)));
    }
    return value;
  }

  String report() => const JsonEncoder.withIndent('  ').convert(
    _safe({
      'produto': 'Jortan Viewer $appVersion',
      'tipoBuild': kReleaseMode ? 'release' : 'debug',
      'compatibilidadeTcp':
          'Normaliza apenas RTP/AVP sem /TCP quando os canais interleaved correspondem ao pedido. A ponte opera só no celular.',
      'build': appBuild,
      'schemaDiagnostico': 2,
      'sistema': Platform.operatingSystemVersion,
      'limites': {
        'testeDireto':
            'Verifica o canal de controle TCP; não testa chegada de RTP/UDP.',
        'primeiroQuadroTimeoutMs': frameTimeout.inMilliseconds,
        'preparacaoTimeoutMs': 24000,
        'semProgressoTimeoutMs': stallTimeout.inMilliseconds,
        'linhasPorTentativa': 320,
      },
      'horario': DateTime.now().toUtc().toIso8601String(),
      'plataforma': defaultTargetPlatform.name,
      'ip': config.host,
      'porta': config.port,
      'caminho': Uri.tryParse(config.path)?.path ?? '[inválido]',
      'transporteSolicitado': config.transport.name,
      'ajusteReproducao': config.tuning.name,
      'atrasoPontaAPontaMedido': false,
      'estado': phase.name,
      'mensagem': message,
      // Keep the control failure ahead of verbose player logs in pasted reports.
      'controlesCamera': controlsReport,
      'tentativas': attempts.map((e) => e.toJson()).toList(),
      'errosDoAplicativo': appErrors,
      'buscaCamera': discoveryReport,
      'escutaAudioSolicitada': audioEnabled,
      'observacao':
          'Credenciais removidas. Avisos não são tratados como causas comprovadas. A ausência de vídeo não comprova bloqueio de firewall.',
    }),
  );

  String briefReport() {
    final attempt = attempts.lastOrNull;
    final events = (controlsReport?['eventos'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final allFaults = events.where((e) => e.containsKey('falhaSoap')).toList();
    final faults = <Map>{
      ...allFaults.take(1),
      ...allFaults.skip(allFaults.length > 3 ? allFaults.length - 3 : 0),
    };
    final errors = events
        .where(
          (e) =>
              e.containsKey('codigo') ||
              e['operacao'] == 'parada_previa_confirmada' ||
              e['operacao'] == 'movimento_manual_solicitado' ||
              e['operacao'] == 'parada_alternativa_solicitada' ||
              (e['etapa'] == 'resposta_validada' &&
                  ['Stop', 'ContinuousMove'].contains(e['operacao'])),
        )
        .toList();
    return const JsonEncoder.withIndent('  ').convert(
      _safe({
        'produto': 'Jortan Viewer $appVersion',
        'tipoBuild': kReleaseMode ? 'release' : 'debug',
        'build': appBuild,
        'horario': DateTime.now().toUtc().toIso8601String(),
        'estado': phase.name,
        'ip': config.host,
        'caminho': Uri.tryParse(config.path)?.path,
        'video': {
          'recebido': attempt?.videoReceived ?? false,
          'transporte': attempt?.transport,
          ...?attempt?.checks['parametros_video'],
        },
        'audio': {
          'anunciado': audioAvailable,
          'escutaSolicitada': audioEnabled,
        },
        'controle': controlsReport?['resultado'],
        'eventosControle': [
          ...faults,
          ...errors.skip(errors.length > 8 ? errors.length - 8 : 0),
        ],
        'aviso':
            'Resumo sem logs de vídeo. Movimento físico e sincronização não foram verificados pelo app.',
      }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    if (!_cancel.isCompleted) _cancel.complete();
    super.dispose();
  }
}
