import 'dart:async';
import 'package:flutter/material.dart';
import 'design.dart';
import 'camera.dart';
import 'onvif.dart';
import 'ptz_motion.dart';

class CameraControls extends StatefulWidget {
  final CameraConfig config;
  final OnvifClient Function(CameraConfig, void Function(Map<String, dynamic>))?
  clientFactory;
  final bool enabled;
  final String? discoveredEndpoint;
  final void Function(Map<String, dynamic>) onReport;
  const CameraControls({
    super.key,
    required this.config,
    required this.enabled,
    this.discoveredEndpoint,
    this.clientFactory,
    required this.onReport,
  });
  @override
  State<CameraControls> createState() => _CameraControlsState();
}

class _CameraControlsState extends State<CameraControls>
    with WidgetsBindingObserver {
  OnvifClient? _client;
  PtzMotion? _motion;
  List<PtzProfile> profiles = [];
  PtzProfile? selected;
  bool checking = false, _disposed = false, allowProfileTest = false;
  String message = 'Verifique os controles que sua câmera oferece.';
  final List<Map<String, dynamic>> events = [];
  int dropped = 0;
  bool continuousPress = false;
  int _activationGeneration = 0;
  Map<String, dynamic> summary = {};
  void _event(Map<String, dynamic> event) {
    if (_disposed) return;
    if (events.length >= 100) {
      events.removeAt(30);
      dropped++;
    }
    events.add({'horario': DateTime.now().toUtc().toIso8601String(), ...event});
    widget.onReport({
      'tipo': 'onvif_ptz',
      'ip': widget.config.host,
      'resultado': summary,
      'eventos': List.of(events),
      'eventosDescartados': dropped,
      'limites': {
        'pulsoMs': 600,
        'pulsoExperimentalMs': 300,
        'consultaOnvifTimeoutMs':
            OnvifClient.defaultRequestTimeout.inMilliseconds,
        'orcamentoEntreConsultasPtzMs':
            OnvifClient.capabilityBudget.inMilliseconds,
        'holdMaximoMs': 5000,
        'observacao':
            'Comando aceito não comprova movimento físico. A parada depende da câmera respeitar Stop/Timeout.',
      },
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(CameraControls old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) {
      ++_activationGeneration;
      allowProfileTest = false;
      continuousPress = false;
      if (summary['testeAtivo'] == true) {
        summary = {...summary, 'testeAtivo': false, 'modoPressao': false};
        _event({
          'operacao': 'teste_manual_desativado',
          'motivo': 'tela_inativa',
        });
      }
      unawaited(_motion?.stop());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      ++_activationGeneration;
      if (mounted) {
        setState(() {
          allowProfileTest = false;
          continuousPress = false;
        });
      }
      if (summary['testeAtivo'] == true) {
        summary = {...summary, 'testeAtivo': false, 'modoPressao': false};
        _event({
          'operacao': 'teste_manual_desativado',
          'motivo': 'aplicativo_inativo',
        });
      }
      unawaited(_motion?.stop());
    }
  }

  @override
  void dispose() {
    _disposed = true;
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
    final failure = error is OnvifFailure
        ? error
        : OnvifFailure(
            'falha_controle',
            'Não foi possível enviar o comando à câmera.',
          );
    summary = {...summary, 'ultimoErro': failure.code};
    if (selected?.requiresTest == true) {
      allowProfileTest = false;
      continuousPress = false;
    }
    ++_activationGeneration;
    if (selected?.requiresTest == true) {
      summary['testeAtivo'] = false;
      summary['modoPressao'] = false;
    }
    _event({'codigo': failure.code});
    if (mounted) setState(() => message = failure.message);
  }

  Future<void> _inspect({bool manualOnly = false}) async {
    setState(() {
      checking = true;
      message = manualOnly
          ? 'Buscando perfis para o teste manual…'
          : 'Verificando ONVIF e perfis de movimento…';
    });
    await _motion?.close();
    _motion = null;
    _client?.close();
    profiles = [];
    selected = null;
    events.clear();
    dropped = 0;
    summary = {};
    final client =
        widget.clientFactory?.call(widget.config, _event) ??
        OnvifClient(widget.config, onEvent: _event);
    _client = client;
    try {
      final found = await client.inspect(
        discoveredEndpoint: widget.discoveredEndpoint,
        manualOnly: manualOnly,
      );
      if (!mounted) return;
      profiles = found;
      selected =
          found.where((p) => p.supported && !p.requiresTest).firstOrNull ??
          found.where((p) => p.supported).firstOrNull ??
          found.first;
      _select(selected!);
      summary = {
        'modo': manualOnly
            ? 'compatibilidade_yoosee_manual'
            : 'onvif_consultado',
        'capacidadesConsultadas': found.any((p) => !p.requiresTest),
        'movimentoVerificado': false,
        'perfis': [
          for (final p in found)
            {
              'nome': p.name,
              'giroInclinacaoContinuos': p.manualYoosee
                  ? null
                  : p.panTilt != null,
              'zoomContinuo': p.manualYoosee ? null : p.zoom != null,
              'fonteCapacidades': p.capabilitySource,
              'requerTesteManual': p.requiresTest,
              'holdMaximoMs': p.requiresTest ? 300 : 5000,
            },
        ],
      };
      _event({'operacao': 'verificacao_concluida'});
      setState(() {});
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _openManual() async {
    final found = _client?.manualCandidates ?? [];
    if (found.isEmpty) return;
    setState(() => checking = true);
    await _motion?.close();
    if (!mounted) return;
    setState(() {
      checking = false;
      profiles = List.of(found);
      _select(profiles.first);
      summary = {
        'modo': 'compatibilidade_yoosee_manual',
        'capacidadesConsultadas': false,
        'movimentoVerificado': false,
      };
    });
    _event({'operacao': 'modo_manual_selecionado', 'candidatos': found.length});
  }

  Future<void> _activateTest() async {
    final profile = selected;
    if (profile == null || !widget.enabled || checking) return;
    setState(() {
      checking = true;
      if (profile.manualYoosee) {
        message = 'Confirmando a resposta ao comando Parar…';
      }
    });
    final generation = _activationGeneration;
    try {
      await _motion?.close();
      if (profile.manualYoosee) await _client!.prepareManual(profile);
      if (!mounted ||
          !widget.enabled ||
          !identical(selected, profile) ||
          generation != _activationGeneration) {
        return;
      }
      setState(() {
        allowProfileTest = true;
        continuousPress = false;
        _motion = _createMotion(profile);
        message =
            'Teste ativo: um toque por direção. Solte para parar. O movimento físico ainda precisa ser conferido.';
        summary = {
          ...summary,
          'ultimoErro': null,
          'testeAtivo': true,
          'modoPressao': false,
          if (profile.manualYoosee)
            'metodoParada': _client!.manualStopMethod(profile),
        };
      });
      _event({
        'operacao': 'teste_manual_ativado',
        'limitePressaoMs': 300,
        'paradaPrevia': profile.manualYoosee,
        'movimentoVerificado': false,
      });
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  void _select(PtzProfile profile) {
    ++_activationGeneration;
    selected = profile;
    allowProfileTest = false;
    summary = {...summary, 'testeAtivo': false, 'modoPressao': false};
    continuousPress = false;
    if (profile.manualYoosee) _client?.setManualHold(profile, false);
    _motion = _createMotion(profile);
    message = profile.manualYoosee
        ? 'Compatibilidade experimental: usa o espaço padrão da câmera e velocidade solicitada de 0,1. Ativar testa primeiro Parar; nenhum movimento é enviado nessa etapa.'
        : profile.requiresTest
        ? 'A câmera anuncia movimento, mas não confirmou as opções. Você pode ativar um teste de toque curto.'
        : profile.supported
        ? 'Segure uma seta para mover. Solte para parar.'
        : 'Este perfil não anunciou movimento contínuo nem zoom contínuo.';
  }

  PtzMotion _createMotion(PtzProfile profile) {
    final short = profile.requiresTest && !continuousPress;
    return PtzMotion(
      interval: short
          ? const Duration(seconds: 1)
          : const Duration(milliseconds: 400),
      holdLimit: short
          ? const Duration(milliseconds: 300)
          : const Duration(seconds: 5),
      move: (x, y, z) => _client!.move(profile, x, y, z),
      halt: () => _client!.stop(profile),
      onError: _error,
    );
  }

  Future<void> _setContinuous(bool value) async {
    final profile = selected;
    if (profile == null ||
        !profile.manualYoosee ||
        !allowProfileTest ||
        !widget.enabled ||
        checking) {
      return;
    }
    final generation = _activationGeneration;
    setState(() => checking = true);
    try {
      await _motion?.close();
      if (!mounted ||
          !widget.enabled ||
          !allowProfileTest ||
          generation != _activationGeneration) {
        return;
      }
      _client!.setManualHold(profile, value);
      setState(() {
        continuousPress = value;
        _motion = _createMotion(profile);
        message = value
            ? 'Segure uma seta para mover. Solte para parar. Limite de 5 segundos por pressão.'
            : 'Teste ativo: um toque por direção. Solte para parar.';
        summary = {...summary, 'modoPressao': value};
      });
      _event({
        'operacao': 'modo_pressao_alterado',
        'ativo': value,
        'holdMaximoMs': value ? 5000 : 300,
        'timeoutCameraMs': value ? 2000 : 300,
      });
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> _changeProfile(PtzProfile profile) async {
    setState(() => checking = true);
    await _motion?.close();
    if (!mounted) return;
    setState(() {
      _select(profile);
      checking = false;
    });
    _event({'operacao': 'perfil_selecionado', 'nome': profile.name});
  }

  Widget _button(
    String label,
    IconData icon,
    int x,
    int y,
    int z,
    bool supported,
  ) => HoldCameraButton(
    label: label,
    icon: icon,
    enabled:
        widget.enabled &&
        supported &&
        !checking &&
        (selected?.requiresTest != true || allowProfileTest),
    onStart: () {
      if (widget.enabled &&
          !checking &&
          (selected?.requiresTest != true || allowProfileTest)) {
        _motion?.start(x, y, z);
      }
    },
    onStop: () => unawaited(_motion?.stop()),
  );
  @override
  Widget build(BuildContext context) {
    final pan = selected?.panTilt != null, zoom = selected?.zoom != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Controle da câmera',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(fontSize: 12, color: textSecondary),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: checking ? null : _inspect,
              icon: checking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.tune),
              label: Text(
                checking ? 'Verificando…' : 'Verificar controles ONVIF',
              ),
            ),
            if (!checking &&
                selected?.manualYoosee != true &&
                widget.enabled) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => unawaited(
                  (_client?.manualCandidates.isNotEmpty ?? false)
                      ? _openManual()
                      : _inspect(manualOnly: true),
                ),
                icon: const Icon(Icons.science_outlined),
                label: const Text('Testar compatibilidade Yoosee'),
              ),
            ],
            if (profiles.length > 1)
              DropdownButton<PtzProfile>(
                isExpanded: true,
                value: selected,
                items: profiles
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: checking
                    ? null
                    : (p) {
                        if (p != null) unawaited(_changeProfile(p));
                      },
              ),
            if (selected?.requiresTest == true) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: widget.enabled && !checking && !allowProfileTest
                    ? () => unawaited(_activateTest())
                    : null,
                icon: const Icon(Icons.touch_app_outlined),
                label: Text(
                  allowProfileTest
                      ? (continuousPress
                            ? 'Controle por pressão ativo'
                            : 'Teste de toque curto ativo')
                      : 'Ativar teste de movimento',
                ),
              ),
            ],
            if (selected?.manualYoosee == true) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Segurar para mover'),
                subtitle: const Text(
                  'Teste primeiro com um toque curto. Por pressão: até 5 segundos; solte para parar.',
                ),
                value: continuousPress,
                onChanged: widget.enabled && allowProfileTest && !checking
                    ? (value) => unawaited(_setContinuous(value))
                    : null,
              ),
            ],
            if (selected != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Column(
                  children: [
                    _button(
                      'Inclinar para cima',
                      Icons.keyboard_arrow_up,
                      0,
                      1,
                      0,
                      pan,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _button(
                          'Girar para a esquerda',
                          Icons.keyboard_arrow_left,
                          -1,
                          0,
                          0,
                          pan,
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Parar movimento',
                          onPressed: () =>
                              unawaited(_motion?.stop(force: true)),
                          icon: const Icon(Icons.stop),
                        ),
                        _button(
                          'Girar para a direita',
                          Icons.keyboard_arrow_right,
                          1,
                          0,
                          0,
                          pan,
                        ),
                      ],
                    ),
                    _button(
                      'Inclinar para baixo',
                      Icons.keyboard_arrow_down,
                      0,
                      -1,
                      0,
                      pan,
                    ),
                    if (selected?.manualYoosee != true) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _button(
                            'Diminuir zoom da câmera',
                            Icons.zoom_out,
                            0,
                            0,
                            -1,
                            zoom,
                          ),
                          const SizedBox(width: 16),
                          _button(
                            'Aumentar zoom da câmera',
                            Icons.zoom_in,
                            0,
                            0,
                            1,
                            zoom,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (!widget.enabled)
                const Text(
                  'Conecte o vídeo e abra a aba Ao vivo para mover.',
                  style: TextStyle(fontSize: 12),
                ),
              if (selected?.manualYoosee == true)
                const Text(
                  'Modo manual sem capacidades confirmadas. Se Parar falhar, as setas ficam bloqueadas. A câmera precisa respeitar a parada e o tempo-limite solicitado. Zoom físico não faz parte deste teste.',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              if (!pan)
                const Text(
                  'Giro e inclinação contínuos não anunciados por este perfil.',
                  style: TextStyle(fontSize: 12),
                ),
              if (!zoom && selected?.manualYoosee != true)
                const Text(
                  'Zoom da câmera não anunciado por este perfil.',
                  style: TextStyle(fontSize: 12),
                ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Se a verificação falhar, abra Diagnóstico e compartilhe o relatório completo. A falha de consulta não confirma ausência de controle.',
              style: TextStyle(fontSize: 11, color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class HoldCameraButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onStart, onStop;
  const HoldCameraButton({
    super.key,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onStart,
    required this.onStop,
  });
  @override
  State<HoldCameraButton> createState() => _HoldCameraButtonState();
}

class _HoldCameraButtonState extends State<HoldCameraButton> {
  bool pressed = false;
  Timer? _accessiblePulse;
  void _start() {
    if (widget.enabled && !pressed) {
      setState(() => pressed = true);
      widget.onStart();
    }
  }

  void _stop() {
    _accessiblePulse?.cancel();
    if (pressed) {
      setState(() => pressed = false);
      widget.onStop();
    }
  }

  @override
  void didUpdateWidget(HoldCameraButton old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) _stop();
  }

  @override
  void dispose() {
    _accessiblePulse?.cancel();
    if (pressed) widget.onStop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    button: true,
    enabled: widget.enabled,
    onTap: !widget.enabled
        ? null
        : () {
            _start();
            _accessiblePulse = Timer(const Duration(milliseconds: 250), _stop);
          },
    child: Tooltip(
      // A long-press tooltip would win the gesture arena after 500 ms and
      // cancel the held direction. Keep hover help and the semantic label.
      triggerMode: TooltipTriggerMode.manual,
      message: widget.label,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTapDown: widget.enabled ? (_) => _start() : null,
        onTapUp: widget.enabled ? (_) => _stop() : null,
        onTapCancel: _stop,
        child: Container(
          width: 48,
          height: 48,
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: pressed
                ? accent
                : Colors.white.withValues(alpha: widget.enabled ? .12 : .03),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            widget.icon,
            color: pressed
                ? onAccent
                : widget.enabled
                ? textPrimary
                : Colors.white38,
          ),
        ),
      ),
    ),
  );
}
