# Imagem, resolução e atraso

A Jortan do usuário entregou 1920×1080 em /onvif1 (Full HD). O app do fabricante pode oferecer rótulos HD/FHD para transmissões diferentes. O teste do usuário confirmou /onvif2 com 640×360, abaixo de HD (1280×720). O app informa a resolução realmente recebida depois do primeiro quadro. Neste teste o SDP do fluxo menor anunciou somente vídeo, enquanto /onvif1 já anunciou PCMA/16000. Use Mais detalhes para testar som; não há sincronização de áudio confirmada.

## Uso

- **Mais detalhes**: seleciona /onvif1 e o ajuste de compatibilidade.
- **Mais fluido**: testa /onvif2 com ajustes para menor atraso. A câmera pode não oferecer esse caminho ou pode devolver uma resolução diferente. Se não abrir, volte para Mais detalhes; as credenciais e o endpoint ONVIF são preservados.
- **Atualizar transmissão**: encerra a sessão e reconecta, descartando o buffer local. Não faz seek em RTSP e não garante que a câmera envie o instante atual sem atraso.
- Para manter um caminho personalizado ou /onvif1 e reduzir buffers, use Câmera → Ajuste de reprodução → Menor atraso e salve/teste. A opção mantém o caminho informado.
- O áudio começa com a faixa desativada, não apenas volume zero. Ouvir câmera ativa a faixa e o volume; Silenciar desativa ambos. Os timestamps de áudio inconsistentes da câmera podem afetar a sincronização quando a escuta estiver ligada.

## Limites

Fluxos menores geralmente exigem menos rede/decodificação, mas não garantem menor atraso. Atraso depende também da câmera, Wi-Fi, timestamps, intervalos de quadro-chave e processamento. O diagnóstico registra ajuste e resolução, mas não mede atraso ponta a ponta. A hora de chegada ou o PTS do vídeo, sem referência confiável da câmera, não permite inventar essa medição.

Os ajustes usam um subconjunto conservador do [perfil low-latency do mpv 0.36](https://github.com/mpv-player/mpv/blob/v0.36.0/etc/builtin.conf): menos leitura adiantada, buffer de áudio pequeno e um thread de decodificação de software. A análise HEVC de 10 segundos foi preservada porque a câmera já falhou ao fornecer dimensões/VPS/SPS/PPS antes de um quadro-chave. Não foi aplicado fflags=nobuffer nem reduzida agressivamente a análise inicial.
