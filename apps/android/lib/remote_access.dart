import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'design.dart';

Uri? remoteAddress(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path != '' && uri.path != '/' ||
      input.length > 2048) {
    return null;
  }
  return uri;
}

class RemoteAccess extends StatefulWidget {
  final bool fullPage;
  final FlutterSecureStorage storage;
  final Future<void> Function(String)? launcher;
  const RemoteAccess({
    super.key,
    this.fullPage = false,
    this.storage = const FlutterSecureStorage(),
    this.launcher,
  });
  @override
  State<RemoteAccess> createState() => _RemoteAccessState();
}

class _RemoteAccessState extends State<RemoteAccess> {
  final address = TextEditingController();
  String? message;
  bool opening = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await widget.storage.read(key: 'remote_url.v1');
      if (mounted && address.text.isEmpty && saved != null) {
        address.text = saved;
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Informe o endereço da ponte do notebook.');
      }
    }
  }

  Future<void> _open() async {
    final uri = remoteAddress(address.text);
    if (uri == null) {
      setState(
        () => message =
            'Cole o endereço HTTPS completo exibido pela ponte, sem senha na URL.',
      );
      return;
    }
    setState(() {
      opening = true;
      message = null;
    });
    try {
      await widget.storage.write(key: 'remote_url.v1', value: uri.toString());
      if (widget.launcher != null) {
        await widget.launcher!(uri.toString());
      } else {
        await const MethodChannel(
          'com.jortanviewer/remote',
        ).invokeMethod<void>('open', {'url': uri.toString()});
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Não foi possível abrir aqui. Você também pode usar esse endereço no Safari ou Chrome.',
        );
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: widget.fullPage
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _fields(),
            )
          : ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Acesso de longe'),
              subtitle: const Text('Pelo notebook Windows'),
              children: _fields(),
            ),
    ),
  );

  List<Widget> _fields() => [
    const Text(
      'Deixe a ponte aberta no notebook e cole o endereço remoto exibido por ela. Use a senha remota para entrar.',
      style: TextStyle(color: textSecondary),
    ),
    const SizedBox(height: 16),
    TextField(
      controller: address,
      keyboardType: TextInputType.url,
      autocorrect: false,
      decoration: const InputDecoration(
        labelText: 'Endereço HTTPS da ponte',
        hintText: 'https://seu-endereco.trycloudflare.com',
      ),
      onSubmitted: (_) {
        if (!opening) _open();
      },
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: opening ? null : _open,
      icon: const Icon(Icons.public),
      label: Text(opening ? 'Abrindo…' : 'Abrir câmera remota'),
    ),
    if (message != null)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(message!, style: const TextStyle(color: textSecondary)),
      ),
    const SizedBox(height: 8),
    const Text(
      'O endereço pode mudar ao reiniciar a ponte. No iPhone, abra-o no Safari e adicione à Tela de Início.',
      style: TextStyle(fontSize: 12, color: textSecondary),
    ),
  ];
}
