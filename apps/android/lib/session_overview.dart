import 'package:flutter/material.dart';
import 'connection.dart';
import 'design.dart';

class SessionOverview extends StatelessWidget {
  final CameraConnection connection;
  const SessionOverview({super.key, required this.connection});
  @override
  Widget build(BuildContext context) {
    final video = connection.attempts.lastOrNull?.checks['parametros_video'];
    final live = connection.phase == ConnectionPhase.live;
    final width = video?['largura'], height = video?['altura'];
    final result = connection.controlsReport?['resultado'] as Map?;
    String control;
    if (result?['modo'] == 'onvif_compativel') {
      control = result?['controleAtivo'] == true
          ? 'Controle conectado'
          : result?['ultimoErro'] != null
          ? 'Controle precisa reconectar'
          : 'Preparando controle';
    } else if (result?['modo'] == 'compatibilidade_yoosee_manual') {
      control = result?['testeAtivo'] == true
          ? 'Teste manual ativo'
          : 'Teste manual aguardando ativação';
    } else if (result?['ultimoErro'] != null) {
      control = 'Controle ainda não confirmado';
    } else if (result?['perfis'] != null) {
      control = 'Perfis consultados · movimento a conferir';
    } else {
      control = 'Controle ainda não verificado';
    }
    Widget fact(IconData icon, String title, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: accent),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(color: textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sua transmissão',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            fact(
              Icons.videocam_outlined,
              live ? 'Vídeo conectado' : 'Vídeo desconectado',
              live && width != null && height != null
                  ? '$width × $height · ${connection.attempts.last.transport.toUpperCase()}'
                  : 'A resolução aparece depois que chegar vídeo.',
            ),
            fact(
              Icons.volume_up_outlined,
              'Som',
              connection.audioAvailable == false
                  ? 'Este fluxo não anunciou áudio.'
                  : connection.audioEnabled
                  ? 'Escuta ativada · sincronização a conferir'
                  : connection.audioAvailable == true
                  ? 'Faixa disponível · escuta desativada'
                  : 'Disponibilidade ainda não identificada',
            ),
            fact(Icons.control_camera_outlined, 'Movimento', control),
          ],
        ),
      ),
    );
  }
}
