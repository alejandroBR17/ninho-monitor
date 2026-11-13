import 'package:flutter/material.dart';

class VideoFullscreenButton extends StatelessWidget {
  final bool fullscreen;
  final VoidCallback onToggle;
  const VideoFullscreenButton({
    super.key,
    required this.fullscreen,
    required this.onToggle,
  });
  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: fullscreen ? 'Sair da tela cheia' : 'Tela cheia',
    onPressed: onToggle,
    icon: Icon(
      fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
    ),
  );
}

class ImageZoomReset extends StatelessWidget {
  final TransformationController controller;
  const ImageZoomReset({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Matrix4>(
    valueListenable: controller,
    builder: (_, matrix, _) => TextButton.icon(
      onPressed: matrix.isIdentity()
          ? null
          : () => controller.value = Matrix4.identity(),
      icon: const Icon(Icons.restart_alt),
      label: const Text('Redefinir zoom'),
    ),
  );
}
