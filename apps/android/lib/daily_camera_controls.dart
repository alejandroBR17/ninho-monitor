import 'dart:async';
import 'package:flutter/material.dart';
import 'camera.dart';
import 'camera_controls.dart' show HoldCameraButton;
import 'control_store.dart';
import 'design.dart';
import 'onvif.dart';
import 'ptz_motion.dart';
import 'camera_joystick.dart';

class DailyCameraControls extends StatefulWidget {
  final CameraConfig config;
  final bool enabled;
  final String? discoveredEndpoint;
  final ControlStore store;
  final OnvifClient Function(CameraConfig, void Function(Map<String, dynamic>))?
  clientFactory;
  final void Function(Map<String, dynamic>) onReport;
  const DailyCameraControls({
    super.key,
    required this.config,
    required this.enabled,
    this.discoveredEndpoint,
    this.store = const ControlStore(),
    this.clientFactory,
    required this.onReport,
  });
  @override
  State<DailyCameraControls> createState() => _DailyCameraControlsState();
}

class _DailyCameraControlsState extends State<DailyCameraControls>
    with WidgetsBindingObserver {
  OnvifClient? _client;
  PtzMotion? _motion;
  PtzProfile? _selected;
  List<PtzProfile> _profiles = [];
  final List<Map<String, dynamic>> _events = [];
  Map<String, dynamic> _summary = {};
  int _generation = 0, _dropped = 0;
  bool _checking = false, _ready = false, _foreground = true, _disposed = false;
  bool _joystick = false, _switching = false;
  int _styleGeneration = 0, _stopRevision = 0;
  String _message = 'O controle fica disponível ao conectar o vídeo.';

  void _event(Map<String, dynamic> event) {
    if (_disposed) return;
    if (_events.length >= 100) {
      _events.removeAt(30);
      _dropped++;
    }
    _events.add({
      'horario': DateTime.now().toUtc().toIso8601String(),
      ...event,
    });
    widget.onReport({
      'tipo': 'onvif_ptz',
      'ip': widget.config.host,
      'resultado': _summary,
      'eventos': List.of(_events),
      'eventosDescartados': _dropped,
      'limites': {
        'holdMaximoMs': 5000,
        'timeoutCameraMs': 2000,
        'consultaOnvifTimeoutMs':
            OnvifClient.defaultRequestTimeout.inMilliseconds,
        'observacao':
            'Parada depende da câmera respeitar velocidade zero/Stop e timeout.',
      },
    });
  }

  Future<void> _loadStyle() async {
    final generation = _styleGeneration;
    try {
      final joystick = await widget.store.loadJoystick();
      if (mounted && !_disposed && generation == _styleGeneration) {
        setState(() => _joystick = joystick);
      }
    } catch (_) {
      _event({'codigo': 'preferencia_interface_indisponivel'});
    }
  }

  Future<void> _changeStyle(bool joystick) async {
    if (_switching || joystick == _joystick) return;
    ++_styleGeneration;
    setState(() => _switching = true);
    await _motion?.stop();
    if (!mounted || _disposed) return;
    setState(() {
      _joystick = joystick;
    });
    try {
      await widget.store.saveJoystick(joystick);
    } catch (_) {
      _event({'codigo': 'preferencia_interface_nao_salva'});
    }
    if (mounted && !_disposed) setState(() => _switching = false);
    _summary = {
      ..._summary,
      'interfaceControle': joystick ? 'joystick' : 'setas',
    };
    _event({'operacao': 'interface_controle_alterada'});
  }

  Future<void> _halt() async {
    setState(() => _stopRevision++);
    await _motion?.stop(force: true);
  }

  void _steer(int x, int y) {
    if ((x == 0 && y == 0) ||
        (_ready &&
            widget.enabled &&
            _foreground &&
            !_checking &&
            !_switching)) {
      _motion?.steer(x, y);
    }
  }

  bool _current(int generation) =>
      !_disposed &&
      mounted &&
      widget.enabled &&
      _foreground &&
      generation == _generation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadStyle());
    scheduleMicrotask(() => unawaited(_connect()));
  }

  @override
  void didUpdateWidget(DailyCameraControls old) {
    super.didUpdateWidget(old);
    if (old.config.host != widget.config.host ||
        old.config.username != widget.config.username ||
        old.config.password != widget.config.password ||
        old.config.onvifUrl != widget.config.onvifUrl) {
      _suspend();
      unawaited(_connect());
    } else if (!widget.enabled && old.enabled) {
      _suspend();
    } else if (widget.enabled && !old.enabled) {
      unawaited(_connect());
    }
  }

  void _suspend() {
    ++_generation;
    _ready = false;
    _summary = {..._summary, 'controleAtivo': false};
    _message = 'O controle fica disponível ao conectar o vídeo.';
    _event({'operacao': 'controle_suspenso'});
    unawaited(_motion?.stop());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _suspend();
      if (mounted) setState(() {});
    } else {
      unawaited(_connect());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    final client = _client, motion = _motion;
    if (motion == null) {
      client?.close();
    } else {
      unawaited(motion.close().whenComplete(() => client?.close()));
    }
    super.dispose();
  }

  void _error(Object error) {
    if (_disposed) return;
    final failure = error is OnvifFailure
        ? error
        : OnvifFailure(
            'falha_controle',
            'Não foi possível preparar o controle. Tente reconectar.',
          );
    ++_generation;
    _ready = false;
    _summary = {
      ..._summary,
      'controleAtivo': false,
      'ultimoErro': failure.code,
    };
    _event({'codigo': failure.code});
    if (mounted) setState(() => _message = failure.message);
  }

  Future<void> _connect({PtzProfile? chosen, bool discover = false}) async {
    if (_disposed ||
        !widget.enabled ||
        !_foreground ||
        _checking ||
        _ready && chosen == null && !discover) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _checking = true;
      _ready = false;
      _selected = null;
      _message = 'Preparando controle da câmera…';
    });
    var interrupted = false;
    try {
      await _motion?.close();
      _motion = null;
      _client?.close();
      if (!_current(generation)) {
        interrupted = true;
        return;
      }
      final client =
          widget.clientFactory?.call(widget.config, _event) ??
          OnvifClient(widget.config, onEvent: _event);
      _client = client;
      _summary = {
        'modo': 'onvif_compativel',
        'controleAtivo': false,
        'capacidadesConsultadas': false,
        'movimentoVerificadoAutomaticamente': false,
      };
      ControlPreference? saved;
      if (!discover && chosen == null) {
        try {
          saved = await widget.store.load(widget.config);
        } catch (_) {
          _event({'codigo': 'preferencia_controle_indisponivel'});
        }
      }
      if (!_current(generation)) {
        interrupted = true;
        return;
      }
      var profile = chosen ?? saved?.profile;
      var prepared = false;
      if (profile != null) {
        try {
          await client.prepareManual(
            profile,
            preferredMinimal: saved?.minimal ?? false,
            preferredZeroStop: saved?.zeroStop ?? true,
          );
          prepared = true;
        } on OnvifFailure {
          if (chosen != null) rethrow;
        }
      }
      if (!_current(generation)) {
        interrupted = true;
        return;
      }
      if (!prepared) {
        _profiles = await client.inspect(
          discoveredEndpoint: widget.discoveredEndpoint,
          manualOnly: true,
        );
        if (!_current(generation)) {
          interrupted = true;
          return;
        }
        if (_profiles.isEmpty) {
          throw OnvifFailure(
            'perfil_indisponivel',
            'A câmera não forneceu um perfil de controle.',
          );
        }
        profile = _profiles.first;
        await client.prepareManual(
          profile,
          preferredMinimal: false,
          preferredZeroStop: true,
        );
      }
      if (!_current(generation)) {
        interrupted = true;
        return;
      }
      final active = profile!;
      _selected = active;
      _profiles = [
        active,
        ..._profiles.where(
          (p) => p.token != active.token || p.endpoint != active.endpoint,
        ),
      ];
      client.setManualHold(active, true);
      _motion = PtzMotion(
        move: (x, y, z) => client.move(active, x, y, z),
        halt: () => client.stop(active),
        onError: _error,
      );
      final preference = ControlPreference(
        host: widget.config.host,
        username: widget.config.username,
        deviceUrl: widget.config.onvifUrl,
        token: active.token,
        endpoint: active.endpoint,
        minimal: client.manualMinimalFormat(active) ?? false,
        zeroStop:
            client.manualStopMethod(active) == 'ContinuousMove_velocidade_zero',
      );
      try {
        await widget.store.save(preference);
      } catch (_) {
        _event({'codigo': 'preferencia_controle_nao_salva'});
      }
      if (!_current(generation)) {
        interrupted = true;
        return;
      }
      setState(() {
        _ready = true;
        _message = 'Segure uma seta ou arraste o joystick. Solte para parar.';
        _summary = {
          ..._summary,
          'controleAtivo': true,
          'modoPressao': true,
          'interfaceControle': _joystick ? 'joystick' : 'setas',
          'ultimoErro': null,
          'metodoParada': client.manualStopMethod(active),
          'configuracaoReutilizada': saved != null && prepared,
        };
      });
      _event({'operacao': 'controle_pronto'});
    } catch (error) {
      if (_current(generation)) {
        _error(error);
      } else {
        interrupted = generation != _generation;
      }
    } finally {
      if (mounted && !_disposed) {
        setState(() => _checking = false);
        if (interrupted && widget.enabled && _foreground) {
          scheduleMicrotask(() => unawaited(_connect()));
        }
      }
    }
  }

  Widget _direction(String label, IconData icon, int x, int y) =>
      HoldCameraButton(
        label: label,
        icon: icon,
        enabled:
            _ready &&
            widget.enabled &&
            _foreground &&
            !_checking &&
            !_switching,
        onStart: () {
          if (_ready &&
              widget.enabled &&
              _foreground &&
              !_checking &&
              !_switching) {
            _motion?.start(x, y, 0);
          }
        },
        onStop: () => unawaited(_motion?.stop()),
      );

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.control_camera_outlined, color: accent),
              SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Controle da câmera',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _message,
            style: const TextStyle(color: textSecondary, fontSize: 12),
          ),
          if (_checking) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.control_camera),
                  label: Text('Setas'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.gamepad_outlined),
                  label: Text('Joystick'),
                ),
              ],
              selected: {_joystick},
              onSelectionChanged: _switching
                  ? null
                  : (values) => unawaited(_changeStyle(values.first)),
              style: SegmentedButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ),
          const SizedBox(height: 16),
          if (_joystick) ...[
            Center(
              child: CameraJoystick(
                stopRevision: _stopRevision,
                enabled:
                    _ready &&
                    widget.enabled &&
                    _foreground &&
                    !_checking &&
                    !_switching,
                onDirection: _steer,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: OutlinedButton.icon(
                onPressed: widget.enabled && _selected != null && !_checking
                    ? () => unawaited(_halt())
                    : null,
                icon: const Icon(Icons.stop),
                label: const Text('Parar'),
              ),
            ),
          ] else
            Center(
              child: Column(
                children: [
                  _direction(
                    'Inclinar para cima',
                    Icons.keyboard_arrow_up,
                    0,
                    1,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _direction(
                        'Girar para esquerda',
                        Icons.chevron_left,
                        -1,
                        0,
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Parar',
                        onPressed:
                            widget.enabled && _selected != null && !_checking
                            ? () => unawaited(_halt())
                            : null,
                        icon: const Icon(Icons.stop),
                      ),
                      _direction(
                        'Girar para direita',
                        Icons.chevron_right,
                        1,
                        0,
                      ),
                    ],
                  ),
                  _direction(
                    'Inclinar para baixo',
                    Icons.keyboard_arrow_down,
                    0,
                    -1,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Até 5 segundos por pressão. A câmera pode levar um instante para responder.',
            style: TextStyle(color: textSecondary, fontSize: 12),
          ),
          if (widget.enabled && !_checking && !_ready) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => unawaited(_connect()),
              icon: const Icon(Icons.refresh),
              label: const Text('Reconectar controle'),
            ),
          ],
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Configurações do controle'),
            children: [
              if (_profiles.length > 1)
                DropdownButton<PtzProfile>(
                  isExpanded: true,
                  value: _selected,
                  items: [
                    for (final p in _profiles)
                      DropdownMenuItem(
                        value: p,
                        child: Text(
                          p.name.replaceAll('teste', 'serviço'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: widget.enabled && !_checking
                      ? (p) {
                          if (p != null) unawaited(_connect(chosen: p));
                        }
                      : null,
                ),
              TextButton.icon(
                onPressed: widget.enabled && !_checking
                    ? () => unawaited(_connect(discover: true))
                    : null,
                icon: const Icon(Icons.search),
                label: const Text('Buscar configuração novamente'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
