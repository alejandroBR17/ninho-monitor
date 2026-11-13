import 'package:flutter/material.dart';
import 'camera.dart';
import 'design.dart';

class ViewingControls extends StatelessWidget {
  final CameraConfig config;
  final bool changing, live;
  final int? width, height;
  final ValueChanged<ViewingPreset> onPreset;
  final VoidCallback onRefresh;
  const ViewingControls({
    super.key,
    required this.config,
    required this.changing,
    required this.live,
    required this.onPreset,
    required this.onRefresh,
    this.width,
    this.height,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Imagem', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<ViewingPreset>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(
                value: ViewingPreset.details,
                label: Text('Mais detalhes'),
              ),
              ButtonSegment(
                value: ViewingPreset.fluid,
                label: Text('Mais fluido'),
              ),
            ],
            style: SegmentedButton.styleFrom(minimumSize: const Size(48, 48)),
            selected: {if (config.preset != null) config.preset!},
            onSelectionChanged: changing
                ? null
                : (selected) {
                    if (selected.isNotEmpty) onPreset(selected.first);
                  },
          ),
          const SizedBox(height: 8),
          Text(
            changing
                ? 'Trocando a transmissão…'
                : live && (width ?? 0) > 0 && (height ?? 0) > 0
                ? 'Recebido: $width × $height${width == 1920 && height == 1080
                      ? ' · Full HD'
                      : width == 1280 && height == 720
                      ? ' · HD'
                      : ''}'
                : 'A resolução será mostrada quando chegar vídeo.',
            style: const TextStyle(color: textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          const Text(
            'Mais fluido testa outra transmissão da câmera com ajustes para menor atraso. Se não abrir, volte para Mais detalhes.',
            style: TextStyle(color: textSecondary, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: live && !changing ? onRefresh : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Atualizar transmissão'),
          ),
        ],
      ),
    ),
  );
}
