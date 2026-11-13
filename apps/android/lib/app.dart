import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'camera.dart';
import 'connection.dart';
import 'native_session.dart';
import 'storage.dart';
import 'version.dart';
import 'discovery.dart';
import 'discovery_screen.dart';
import 'daily_camera_controls.dart';
import 'design.dart';
import 'viewing_controls.dart';
import 'session_overview.dart';
import 'video_actions.dart';
import 'remote_access.dart';

class JortanApp extends StatelessWidget {
  const JortanApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Jortan Viewer',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: const ViewerHome(),
  );
}

class ViewerHome extends StatefulWidget {
  const ViewerHome({super.key});
  @override
  State<ViewerHome> createState() => _ViewerHomeState();
}

class _ViewerHomeState extends State<ViewerHome> with WidgetsBindingObserver {
  final connection = CameraConnection(factory: NativeSession.new);
  final store = const CameraStore();
  CameraConfig config = const CameraConfig();
  int tab = 0;
  bool loaded = false, configured = false, keepAwake = true;
  final imageTransform = TransformationController();
  String? storageError;
  bool changingPreset = false;
  bool capturing = false;

  Future<void> _toggleVideoFullscreen(VideoState state) async {
    try {
      await state.toggleFullscreen();
    } catch (error, stack) {
      connection.recordAppError('tela_cheia', error, stack);
      _snack('Não foi possível alternar a tela cheia. Consulte o diagnóstico.');
    }
  }

  Future<void> _shareFrame(BuildContext buttonContext) async {
    if (capturing) return;
    setState(() => capturing = true);
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final bytes = await connection.captureFrame();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png')],
          fileNameOverrides: [
            'jortan-${DateTime.now().millisecondsSinceEpoch}.png',
          ],
          title: 'Imagem da câmera',
          sharePositionOrigin: origin,
        ),
      );
    } catch (error, stack) {
      connection.recordAppError('capturar_imagem', error, stack);
      _snack(
        'Não foi possível capturar a imagem. Confira se o vídeo está conectado.',
      );
    } finally {
      if (mounted) setState(() => capturing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    connection.addListener(_updateWakeLock);
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await store.load();
      if (!mounted) return;
      setState(() {
        if (saved != null) {
          config = saved;
          configured = true;
        }
        loaded = true;
      });
    } catch (error, stack) {
      connection.recordAppError(
        'ler_configuracao',
        error,
        stack,
        sensitive: true,
      );
      if (mounted) {
        setState(() {
          loaded = true;
          storageError =
              'Não foi possível ler a configuração protegida. Configure novamente.';
        });
      }
    }
  }

  void _updateWakeLock() {
    unawaited(
      WakelockPlus.toggle(
        enable: keepAwake && connection.phase == ConnectionPhase.live,
      ).catchError((Object error, StackTrace stack) {
        connection.recordAppError('tela_ligada', error, stack);
      }),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(
        connection.disconnect(
          reason:
              'Vídeo pausado ao sair do app. Toque em conectar para voltar.',
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    connection.removeListener(_updateWakeLock);
    connection.dispose();
    imageTransform.dispose();
    unawaited(
      WakelockPlus.disable().catchError((Object error, StackTrace stack) {
        connection.recordAppError('tela_ligada', error, stack);
      }),
    );
    super.dispose();
  }

  Future<void> _save(CameraConfig next, bool test) async {
    await connection.disconnect();
    connection.redactor.add(next);
    try {
      await store.save(next);
    } catch (error, stack) {
      connection.recordAppError(
        'salvar_configuracao',
        error,
        stack,
        sensitive: true,
      );
      rethrow;
    }
    if (!mounted) return;
    setState(() {
      config = next;
      configured = true;
      storageError = null;
      tab = 0;
    });
    if (test) await connection.connect(next);
  }

  Future<void> _forget() async {
    await connection.disconnect();
    try {
      await store.clear();
      if (!mounted) return;
      setState(() {
        config = const CameraConfig();
        configured = false;
      });
      _snack('Dados da câmera removidos deste aparelho.');
    } catch (error, stack) {
      connection.recordAppError(
        'remover_configuracao',
        error,
        stack,
        sensitive: true,
      );
      _snack('Não foi possível remover os dados. Tente novamente.');
    }
  }

  Future<void> _choosePreset(ViewingPreset preset) async {
    if (changingPreset || config.preset == preset) return;
    setState(() => changingPreset = true);
    try {
      imageTransform.value = Matrix4.identity();
      await _save(config.withPreset(preset), true);
    } catch (_) {
      _snack('Não foi possível salvar a preferência de imagem.');
    } finally {
      if (mounted) setState(() => changingPreset = false);
    }
  }

  void _snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: connection,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.camera_outdoor_rounded, color: accent),
            ),
            const SizedBox(width: 16),
            const Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'jortan viewer',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: IndexedStack(
                    index: tab,
                    children: [
                      _live(),
                      CameraSettings(
                        key: ValueKey(
                          '$configured:${config.host}:${config.path}:${config.transport.name}:${config.tuning.name}',
                        ),
                        initial: config,
                        onSave: _save,
                        onBeforeDiscovery: () => connection.disconnect(
                          reason:
                              'Vídeo encerrado para buscar câmeras na rede.',
                        ),
                        onDiscoveryReport: (report) {
                          connection.discoveryReport = report;
                        },
                        onForget: configured ? _forget : null,
                      ),
                      _diagnostics(),
                      _remote(),
                    ],
                  ),
                ),
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: const [0, 3, 1, 2].indexOf(tab),
        onDestinationSelected: (value) =>
            setState(() => tab = const [0, 3, 1, 2][value]),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam_rounded),
            label: 'Ao vivo',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: 'Remoto',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            label: 'Câmera',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            label: 'Diagnóstico',
          ),
        ],
      ),
    ),
  );

  String? get _discoveredOnvif {
    final devices = connection.discoveryReport?['dispositivos'];
    if (devices is List) {
      for (final device in devices) {
        if (device is Map && device['ip'] == config.host) {
          return device['servicoOnvif'] as String?;
        }
      }
    }
    return null;
  }

  Widget _live() {
    final live = connection.phase == ConnectionPhase.live;
    final busy = connection.active;
    final controller = connection.session?.video;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        const Text(
          'Sua câmera.',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Acompanhe ao vivo pela rede de casa.',
          style: TextStyle(color: textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'REDE DE CASA',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
            ),
            Icon(Icons.circle, size: 8, color: live ? accent : Colors.white38),
            const SizedBox(width: 8),
            Text(
              live
                  ? 'Ao vivo'
                  : busy
                  ? 'Conectando'
                  : 'Desconectada',
              style: TextStyle(
                fontSize: 12,
                color: live ? accent : textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: const Color(0xFF081213),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (controller != null)
                    InteractiveViewer(
                      transformationController: imageTransform,
                      minScale: 1,
                      maxScale: 4,
                      child: Video(
                        key: ObjectKey(controller),
                        controller: controller,
                        wakelock: false,
                        controls: (state) => Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: VideoFullscreenButton(
                              fullscreen: state.isFullscreen(),
                              onToggle: () =>
                                  unawaited(_toggleVideoFullscreen(state)),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: accent.withValues(alpha: .15),
                              ),
                              color: accent.withValues(alpha: .04),
                            ),
                            child: const Icon(
                              Icons.videocam_outlined,
                              color: accent,
                              size: 44,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            configured
                                ? 'Pronta para conectar'
                                : 'Vamos encontrar sua câmera',
                            style: const TextStyle(
                              color: textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (controller != null && !live)
                    const Center(child: CircularProgressIndicator()),
                  Positioned(
                    top: 16,
                    left: 16,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Text(
                          'CÂMERA LOCAL',
                          style: TextStyle(fontSize: 9, letterSpacing: 1.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (live)
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Zoom da imagem: aproxime com dois dedos.',
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ),
              ImageZoomReset(controller: imageTransform),
            ],
          ),
        const SizedBox(height: 16),
        Text(
          configured ? 'Conexão local' : 'Comece pela sua câmera',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          connection.message,
          style: TextStyle(
            color: connection.phase == ConnectionPhase.failed
                ? Colors.orange.shade200
                : textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        if (storageError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              storageError!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () {
            if (busy) {
              unawaited(connection.disconnect());
            } else if (!configured) {
              setState(() => tab = 1);
            } else {
              unawaited(connection.connect(config));
            }
          },
          icon: Icon(
            busy
                ? Icons.stop_rounded
                : configured
                ? Icons.play_arrow_rounded
                : Icons.add_rounded,
          ),
          label: Text(
            busy
                ? 'Desconectar'
                : configured
                ? 'Conectar à câmera'
                : 'Configurar minha câmera',
          ),
        ),
        if (configured) ...[
          const SizedBox(height: 16),
          Builder(
            builder: (buttonContext) => OutlinedButton.icon(
              onPressed: live && !capturing
                  ? () => unawaited(_shareFrame(buttonContext))
                  : null,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(
                capturing ? 'Preparando imagem…' : 'Compartilhar imagem',
              ),
            ),
          ),
          const SizedBox(height: 16),
          DailyCameraControls(
            key: ObjectKey(config),
            config: config,
            enabled: live && tab == 0,
            discoveredEndpoint: _discoveredOnvif,
            onReport: (report) {
              connection.controlsReport = report;
            },
          ),
          const SizedBox(height: 16),
          Card(
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              childrenPadding: const EdgeInsets.all(16),
              leading: const Icon(Icons.tune_rounded, color: accent),
              title: const Text('Imagem e som'),
              subtitle: const Text('Qualidade, áudio e tela'),
              children: [
                ViewingControls(
                  config: config,
                  changing: changingPreset,
                  live: live,
                  width:
                      connection
                              .attempts
                              .lastOrNull
                              ?.checks['parametros_video']?['largura']
                          as int?,
                  height:
                      connection
                              .attempts
                              .lastOrNull
                              ?.checks['parametros_video']?['altura']
                          as int?,
                  onPreset: (preset) => unawaited(_choosePreset(preset)),
                  onRefresh: () => unawaited(connection.connect(config)),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed:
                      live &&
                          !connection.audioChanging &&
                          (connection.audioAvailable != false ||
                              connection.audioEnabled)
                      ? () => unawaited(connection.toggleAudio())
                      : null,
                  icon: Icon(
                    connection.audioEnabled
                        ? Icons.volume_up
                        : Icons.volume_off,
                  ),
                  label: Text(
                    connection.audioEnabled
                        ? 'Silenciar câmera'
                        : 'Ouvir câmera',
                  ),
                ),
                Text(
                  connection.audioError ??
                      (connection.audioAvailable == false
                          ? 'Este fluxo não anunciou áudio. Use Mais detalhes para testar o som.'
                          : connection.audioEnabled
                          ? 'Escuta ativada. Se não houver som, confira os parâmetros de áudio no diagnóstico.'
                          : 'Áudio desativado para priorizar o vídeo. Ative somente quando quiser ouvir.'),
                  style: const TextStyle(fontSize: 11, color: textSecondary),
                ),
                SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: const Text(
                    'Manter a tela ligada',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Somente durante o vídeo ao vivo',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: keepAwake,
                  onChanged: (value) {
                    setState(() => keepAwake = value);
                    _updateWakeLock();
                  },
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wifi_rounded, size: 20, color: textSecondary),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Fora de casa? Use a aba Remoto para acessar pelo notebook.',
                style: TextStyle(color: textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
        if (connection.phase == ConnectionPhase.failed)
          TextButton.icon(
            onPressed: () => setState(() => tab = 2),
            icon: const Icon(Icons.monitor_heart_outlined),
            label: const Text('Ver o que aconteceu'),
          ),
      ],
    );
  }

  Widget _remote() => ListView(
    padding: const EdgeInsets.all(24),
    children: const [
      Text(
        'Perto, de qualquer lugar.',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
      ),
      SizedBox(height: 8),
      Text(
        'Seu notebook conecta a câmera ao seu celular.',
        style: TextStyle(color: textSecondary, height: 1.5),
      ),
      SizedBox(height: 24),
      RemoteAccess(fullPage: true),
      SizedBox(height: 24),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.laptop_rounded, color: accent),
        title: Text('Mantenha a ponte aberta'),
        subtitle: Text('Notebook ligado, na tomada e na rede da câmera.'),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.lock_outline_rounded, color: accent),
        title: Text('Entre com a senha remota'),
        subtitle: Text('A senha da câmera continua no notebook.'),
      ),
    ],
  );

  Widget _diagnostics() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Text(
        'Entenda a conexão.',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: -.8,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Cada transporte tem seu próprio resultado. '
        'Inclui teste RTSP, versões do motor e etapas com horário. Credenciais são removidas.',
        style: TextStyle(color: textSecondary, height: 1.5),
      ),
      const SizedBox(height: 16),
      SessionOverview(connection: connection),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: !connection.hasDiagnostics
            ? null
            : () async {
                try {
                  await Clipboard.setData(
                    ClipboardData(text: connection.briefReport()),
                  );
                  _snack('Resumo copiado, sem registros extensos de vídeo.');
                } catch (error, stack) {
                  connection.recordAppError('copiar_resumo', error, stack);
                  _snack('Não foi possível copiar o resumo.');
                }
              },
        icon: const Icon(Icons.summarize_outlined),
        label: const Text('Copiar resumo curto'),
      ),
      const SizedBox(height: 16),
      const Text(
        'Diagnóstico $appVersion · relatório completo em JSON',
        style: TextStyle(fontSize: 11, color: textSecondary),
      ),
      if (connection.controlsReport != null)
        ExpansionTile(
          title: const Text('Controles ONVIF e movimento'),
          children: [
            SelectableText(
              const JsonEncoder.withIndent(
                '  ',
              ).convert(connection.controlsReport),
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      if (connection.discoveryReport != null)
        ExpansionTile(
          title: const Text('Busca de câmeras na rede'),
          children: [
            SelectableText(
              const JsonEncoder.withIndent(
                '  ',
              ).convert(connection.discoveryReport),
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      if (connection.appErrors.isNotEmpty)
        ExpansionTile(
          title: const Text('Eventos do aplicativo'),
          children: [
            SelectableText(
              const JsonEncoder.withIndent('  ').convert(connection.appErrors),
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      const SizedBox(height: 24),
      if (connection.attempts.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.monitor_heart_outlined, color: accent, size: 36),
                SizedBox(height: 16),
                Text('Ainda não há tentativas'),
                SizedBox(height: 8),
                Text(
                  'Configure a câmera e toque em conectar.',
                  style: TextStyle(color: textSecondary),
                ),
              ],
            ),
          ),
        )
      else
        ...connection.attempts.map(
          (attempt) => Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ExpansionTile(
              shape: const Border(),
              leading: Icon(
                attempt.videoReceived
                    ? Icons.check_circle_outline
                    : Icons.radar_rounded,
                color: attempt.videoReceived ? accent : Colors.orange.shade200,
              ),
              title: Text(
                '${attempt.transport.toUpperCase()} · ${attempt.round == 0 ? 'Conexão inicial' : 'Reconexão ${attempt.round}'}',
              ),
              subtitle: Text(
                attempt.videoReceived
                    ? 'Vídeo recebido'
                    : attempt.ended == null
                    ? 'Aguardando vídeo'
                    : 'Sem vídeo',
                style: const TextStyle(fontSize: 12),
              ),
              childrenPadding: const EdgeInsets.all(16),
              children: [
                if (attempt.finding != null) ...[
                  Text(
                    attempt.finding!.message,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Classificação: ${attempt.finding!.confidence.replaceAll('_', ' ')}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                ],
                if (attempt.checks.isNotEmpty)
                  ExpansionTile(
                    title: const Text(
                      'Teste RTSP e motor',
                      style: TextStyle(fontSize: 13),
                    ),
                    children: [
                      SelectableText(
                        const JsonEncoder.withIndent(
                          '  ',
                        ).convert(attempt.checks),
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                if (attempt.droppedLogs > 0)
                  Text(
                    '${attempt.droppedLogs} linhas intermediárias descartadas; início e fim preservados.',
                  ),
                SelectableText(
                  attempt.result,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  attempt.logs.join('\n'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          OutlinedButton.icon(
            onPressed: !connection.hasDiagnostics
                ? null
                : () async {
                    try {
                      final report = connection.report();
                      if (utf8.encode(report).length > 400000) {
                        _snack(
                          'Relatório grande: use Compartilhar arquivo para enviar tudo.',
                        );
                        return;
                      }
                      await Clipboard.setData(ClipboardData(text: report));
                      _snack('Relatório copiado.');
                    } catch (error, stack) {
                      connection.recordAppError(
                        'copiar_relatorio',
                        error,
                        stack,
                      );
                      _snack(
                        'Não foi possível copiar. Use Compartilhar arquivo.',
                      );
                    }
                  },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar relatório'),
          ),
          Builder(
            builder: (buttonContext) => FilledButton.icon(
              onPressed: !connection.hasDiagnostics
                  ? null
                  : () async {
                      final box =
                          buttonContext.findRenderObject() as RenderBox?;
                      try {
                        await SharePlus.instance.share(
                          ShareParams(
                            text:
                                'Diagnóstico Jortan Viewer $appVersion — relatório JSON em anexo.',
                            files: [
                              XFile.fromData(
                                Uint8List.fromList(
                                  utf8.encode(connection.report()),
                                ),
                                mimeType: 'application/json',
                              ),
                            ],
                            fileNameOverrides: ['jortan-diagnostico.json'],
                            title: 'Diagnóstico Jortan Viewer',
                            sharePositionOrigin: box == null
                                ? null
                                : box.localToGlobal(Offset.zero) & box.size,
                          ),
                        );
                      } catch (error, stack) {
                        connection.recordAppError(
                          'compartilhar_relatorio',
                          error,
                          stack,
                        );
                        _snack(
                          'Não foi possível compartilhar. Use copiar relatório.',
                        );
                      }
                    },
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Compartilhar arquivo'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const Text(
        'Antes de testar',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        '• Confira se RTSP/ONVIF está habilitado no Yoosee.\n'
        '• Use a senha local da câmera, que pode ser diferente da conta Yoosee.\n'
        '• Evite Wi-Fi de convidados com isolamento de dispositivos.\n'
        '• Se /onvif1 não funcionar, teste /onvif2 na configuração.\n'
        '• No iPhone, permita o acesso à Rede Local quando solicitado.',
        style: TextStyle(color: textSecondary, height: 1.9, fontSize: 13),
      ),
      const SizedBox(height: 24),
      TextButton(
        onPressed: () => showLicensePage(
          context: context,
          applicationName: 'Jortan Viewer',
          applicationVersion: appVersion,
          applicationLegalese:
              'App independente, sem vínculo com Jortan ou Yoosee.',
        ),
        child: const Text('Sobre o app e licenças'),
      ),
    ],
  );
}

class CameraSettings extends StatefulWidget {
  final CameraConfig initial;
  final Future<void> Function(CameraConfig, bool) onSave;
  final Future<void> Function()? onForget;
  final void Function(Map<String, dynamic>)? onDiscoveryReport;
  final Future<void> Function()? onBeforeDiscovery;
  const CameraSettings({
    super.key,
    required this.initial,
    required this.onSave,
    this.onForget,
    this.onDiscoveryReport,
    this.onBeforeDiscovery,
  });
  @override
  State<CameraSettings> createState() => _CameraSettingsState();
}

class _CameraSettingsState extends State<CameraSettings> {
  final form = GlobalKey<FormState>();
  late final TextEditingController host,
      port,
      username,
      password,
      path,
      onvifUrl;
  late Transport transport;
  late PlaybackTuning tuning;
  bool obscure = true, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    host = TextEditingController(text: widget.initial.host);
    port = TextEditingController(text: '${widget.initial.port}');
    username = TextEditingController(text: widget.initial.username);
    password = TextEditingController(text: widget.initial.password);
    path = TextEditingController(text: widget.initial.path);
    onvifUrl = TextEditingController(text: widget.initial.onvifUrl);
    transport = widget.initial.transport;
    tuning = widget.initial.tuning;
  }

  @override
  void dispose() {
    for (final field in [host, port, username, password, path, onvifUrl]) {
      field.dispose();
    }
    super.dispose();
  }

  CameraConfig _value() => CameraConfig(
    host: host.text.trim(),
    port: int.tryParse(port.text) ?? 0,
    username: username.text.trim(),
    password: password.text,
    path: path.text.trim(),
    onvifUrl: onvifUrl.text.trim(),
    transport: transport,
    tuning: tuning,
  );
  Future<void> _submit(bool test) async {
    if (!form.currentState!.validate()) return;
    final value = _value();
    final invalid = value.validate();
    if (invalid != null) {
      setState(() => error = invalid);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(value, test);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Não foi possível salvar no armazenamento protegido. Tente novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _findCamera() async {
    await widget.onBeforeDiscovery?.call();
    if (!mounted) return;
    final selected = await Navigator.of(context).push<DiscoveryDevice>(
      MaterialPageRoute(
        builder: (context) => DiscoveryScreen(
          initialHost: host.text.trim(),
          initialPort: int.tryParse(port.text) ?? 554,
          onReport: widget.onDiscoveryReport,
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      host.text = selected.host;
      port.text = '${selected.port}';
      onvifUrl.text = selected.onvifEndpoint ?? '';
      error = null;
    });
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, hintText: hint),
      keyboardType: keyboard,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.next,
      validator: (text) =>
          text == null || text.trim().isEmpty ? 'Preencha este campo.' : null,
    ),
  );
  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Encontre sua câmera.',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Use os dados de acesso local RTSP/ONVIF da sua Jortan.',
          style: TextStyle(color: textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: saving ? null : _findCamera,
          icon: const Icon(Icons.radar_rounded),
          label: const Text('Buscar câmera no Wi-Fi'),
        ),
        const SizedBox(height: 16),
        _field(
          host,
          'IP da câmera',
          keyboard: TextInputType.url,
          hint: '192.168.1.100',
        ),
        _field(port, 'Porta RTSP', keyboard: TextInputType.number),
        _field(username, 'Usuário local'),
        TextFormField(
          controller: password,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Senha local da câmera',
            helperText: 'Protegida neste aparelho. Não aparece nos relatórios.',
            helperMaxLines: 2,
            suffixIcon: IconButton(
              tooltip: obscure ? 'Mostrar senha' : 'Ocultar senha',
              onPressed: () => setState(() => obscure = !obscure),
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _field(path, 'Caminho RTSP', hint: '/onvif1'),
        Wrap(
          spacing: 10,
          children: ['/onvif1', '/onvif2']
              .map(
                (value) => ActionChip(
                  label: Text(value),
                  onPressed: () => setState(() => path.text = value),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 24),
        DropdownButtonFormField<Transport>(
          isExpanded: true,
          initialValue: transport,
          decoration: const InputDecoration(labelText: 'Transporte'),
          items: const [
            DropdownMenuItem(
              value: Transport.automatic,
              child: Text('Automático · TCP, depois UDP'),
            ),
            DropdownMenuItem(value: Transport.tcp, child: Text('Somente TCP')),
            DropdownMenuItem(value: Transport.udp, child: Text('Somente UDP')),
          ],
          onChanged: (value) => setState(() => transport = value!),
        ),
        const SizedBox(height: 16),
        const Text(
          'Os caminhos variam por modelo. O modo automático não garante compatibilidade.',
          style: TextStyle(fontSize: 11, color: textSecondary, height: 1.5),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<PlaybackTuning>(
          initialValue: tuning,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Ajuste de reprodução'),
          items: const [
            DropdownMenuItem(
              value: PlaybackTuning.compatible,
              child: Text('Compatibilidade'),
            ),
            DropdownMenuItem(
              value: PlaybackTuning.responsive,
              child: Text('Menor atraso'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => tuning = value);
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: onvifUrl,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'URL ONVIF (opcional)',
            hintText: 'Preenchida pela busca, quando disponível',
            helperText:
                'Deixe vazia para testar as portas mais comuns. Não inclua senha.',
            helperMaxLines: 2,
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: saving ? null : () => _submit(true),
          icon: saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded),
          label: Text(saving ? 'Salvando…' : 'Salvar e testar conexão'),
        ),
        TextButton(
          onPressed: saving ? null : () => _submit(false),
          child: const Text('Salvar para depois'),
        ),
        if (widget.onForget != null)
          TextButton(
            onPressed: saving
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Esquecer esta câmera?'),
                        content: const Text(
                          'Os dados salvos serão removidos deste aparelho.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Esquecer'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) await widget.onForget!();
                  },
            child: const Text(
              'Esquecer câmera',
              style: TextStyle(color: textSecondary),
            ),
          ),
      ],
    ),
  );
}
