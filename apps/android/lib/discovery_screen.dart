import 'package:flutter/material.dart';
import 'design.dart';
import 'discovery.dart';

class DiscoveryScreen extends StatefulWidget {
  final String initialHost;
  final int initialPort;
  final void Function(Map<String, dynamic>)? onReport;
  final CameraDiscovery Function()? factory;
  final Future<List<String>> Function()? rangeLoader;
  const DiscoveryScreen({
    super.key,
    required this.initialHost,
    this.initialPort = 554,
    this.onReport,
    this.factory,
    this.rangeLoader,
  });
  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen>
    with WidgetsBindingObserver {
  final range = TextEditingController();
  CameraDiscovery? scanner;
  DiscoveryReport? report;
  bool loading = true, searching = false;
  String? message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRanges();
  }

  Future<void> _loadRanges() async {
    try {
      final found = await (widget.rangeLoader ?? CameraDiscovery.localRanges)();
      if (!mounted) return;
      range.text =
          found.firstOrNull ??
          DiscoveryRange.parse('${widget.initialHost}/24').toString();
      if (found.isEmpty) {
        message =
            'Não identifiquei a interface Wi-Fi. Confira a faixa abaixo antes de buscar.';
      }
    } catch (_) {
      if (!mounted) return;
      try {
        range.text = DiscoveryRange.parse(
          '${widget.initialHost}/24',
        ).toString();
      } catch (_) {
        range.text = '192.168.1.0/24';
      }
      message = 'Conecte-se ao Wi-Fi da câmera e confira a faixa de endereços.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      scanner?.cancel();
    }
  }

  @override
  void dispose() {
    scanner?.cancel();
    range.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _search() async {
    DiscoveryRange network;
    try {
      network = DiscoveryRange.parse(range.text);
    } on FormatException catch (error) {
      setState(() => message = error.message);
      return;
    }
    final discovery = (widget.factory ?? CameraDiscovery.new)();
    scanner = discovery;
    setState(() {
      searching = true;
      message = null;
      report = null;
    });
    try {
      final result = await discovery.search(
        network,
        ports: {
          widget.initialPort,
          554,
          8554,
        }.where((port) => port >= 1 && port <= 65535).toList(),
        onUpdate: (update) {
          if (!mounted) return;
          setState(() => report = update);
        },
      );
      widget.onReport?.call(result.toJson());
      if (mounted) setState(() => report = result);
    } catch (error) {
      if (mounted) {
        setState(
          () => message =
              'Não foi possível concluir a busca. Confira o Wi-Fi e a permissão de Rede Local.',
        );
      }
      widget.onReport?.call({
        'erro': error.runtimeType.toString(),
        'faixa': network.toString(),
      });
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = report;
    final found = current?.found ?? const <DiscoveryDevice>[];
    final iphone = Theme.of(context).platform == TargetPlatform.iOS;
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar câmera')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.radar_rounded, size: 45, color: Color(0xFF77E2C2)),
            const SizedBox(height: 16),
            const Text(
              'Encontre na sua rede.',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              iphone
                  ? 'Conecte o iPhone ao Wi-Fi da câmera e permita o acesso à Rede Local quando solicitado.'
                  : 'Conecte o celular ao mesmo Wi-Fi da câmera.',
              style: const TextStyle(height: 1.5, color: textSecondary),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: range,
              enabled: !searching && !loading,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Faixa de endereços',
                hintText: '192.168.1.0/24',
                helperText: 'Busca limitada a até 254 endereços por vez.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: loading
                  ? null
                  : searching
                  ? () => scanner?.cancel()
                  : _search,
              icon: Icon(searching ? Icons.stop_rounded : Icons.search_rounded),
              label: Text(searching ? 'Cancelar busca' : 'Buscar agora'),
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  message!,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    height: 1.5,
                  ),
                ),
              ),
            if (current != null) ...[
              const SizedBox(height: 24),
              LinearProgressIndicator(
                value: searching
                    ? (current.total == 0
                          ? null
                          : current.completed / current.total)
                    : 1,
              ),
              const SizedBox(height: 8),
              Text(
                '${current.completed}/${current.total} testes de porta · ${found.length} dispositivo(s)',
                style: const TextStyle(fontSize: 12, color: textSecondary),
              ),
              if (!searching && current.cancelled)
                const Text(
                  'Busca interrompida. Os resultados encontrados continuam disponíveis.',
                ),
              if (!searching && found.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nenhum dispositivo identificado. Confira a faixa, a permissão de Rede Local e se o Wi-Fi permite comunicação entre aparelhos. Você ainda pode informar o IP manualmente.',
                    style: TextStyle(height: 1.6),
                  ),
                ),
              ...current.warnings.map(
                (warning) => Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    warning,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            ...found.map(
              (device) => Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const Icon(
                    Icons.videocam_outlined,
                    color: Color(0xFF77E2C2),
                  ),
                  title: Text(
                    device.name?.isNotEmpty == true
                        ? device.name!
                        : device.onvif
                        ? 'Dispositivo ONVIF'
                        : 'Dispositivo RTSP',
                  ),
                  subtitle: Text(
                    '${device.host} · porta ${device.port}\n${device.rtspConfirmed ? 'RTSP respondeu${device.onvif ? ' · ONVIF identificado' : ''}' : 'ONVIF identificado; porta RTSP ainda não confirmada'}',
                    style: const TextStyle(fontSize: 12, height: 1.6),
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    scanner?.cancel();
                    Navigator.pop(context, device);
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Toque em um resultado para preencher IP e porta. Usuário e senha continuam no formulário; a busca não testa senhas.',
              style: TextStyle(color: textSecondary, fontSize: 12, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
