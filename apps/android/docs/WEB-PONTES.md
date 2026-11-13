# Opções de ponte para o navegador

A ponte recebe o RTSP da câmera e entrega um fluxo reproduzível no Safari/Chrome. Ela precisa estar ligada e conseguir acessar a câmera enquanto alguém assiste. A página pode ser hospedada na própria ponte junto da API, evitando depender do PC para usar o iPhone.

| Equipamento | Condição |
| --- | --- |
| PC Windows/Linux | Caminho simples para começar; fica ligado durante o uso. |
| Mini PC ou Raspberry Pi | Alternativa dedicada ao PC principal; capacidade depende de precisar converter vídeo ou apenas repassar o fluxo. |
| NAS compatível | Pode aproveitar um equipamento já ligado, se suportar o programa/containers e os codecs necessários. |
| Roteador compatível | Depende de modelo, firmware, memória e CPU. Não prometer instalação em roteador comum. |
| Android/TV box dedicado | Exigiria adaptação, serviço persistente, alimentação e testes de suspensão/desempenho; não há pacote pronto entregue. |
| Servidor na nuvem | Exige alcançar a rede privada, por exemplo por VPN, e pode gerar custos de servidor/tráfego. Hospedar uma página pública não dá acesso ao IP 192.168.1.100. |

## Programas possíveis

- [go2rtc](https://github.com/AlexxIT/go2rtc): software MIT, com binários Windows/Linux/ARM, instalação em Docker/Home Assistant e saídas WebRTC/HLS. É uma opção para avaliação, não uma compatibilidade já confirmada nesta Jortan.
- [MediaMTX](https://mediamtx.org/docs/read/web-browsers): servidor de mídia que permite reprodução e incorporação por WebRTC/HLS. Conversão de codec pode exigir FFmpeg ou outro processo; não presumir transcodificação automática.

A Jortan foi observada com H.265 1920×1080 e PCMA a 16 kHz. Funcionar no VLC para iPhone confirma o fluxo nesse aplicativo, mas não a compatibilidade no Safari. Pode ser necessário converter áudio e/ou vídeo conforme versão do navegador, saída escolhida e codecs negociados. O custo de CPU para converter vídeo é diferente de apenas repassar dados; escolher o equipamento depois dessa avaliação.

A ponte de vídeo não resolve por si só os comandos ONVIF/PTZ. O site precisa de API de controle própria e o firmware precisa aceitar os comandos. A seleção de endpoints e os limites de movimento devem preservar as mesmas verificações do app.

Ainda não foi escolhida nem instalada uma ponte web na casa do usuário. O modelo do roteador e equipamentos disponíveis foram solicitados para decidir sem recomendar compras desnecessárias. O projeto Flutter/Android e a página de download continuam sendo as entregas prontas; não afirmar que a versão web de visualização já está publicada.


## Equipamentos informados pelo usuário

Em 06/11/2026, o usuário informou um Huawei OptiXstar HG8145X6-10-V2 fornecido pela TIM e que não tem NAS, Raspberry Pi, mini PC nem TV box Android. Não considerar esses equipamentos disponíveis. Não foi confirmado suporte documentado para instalar go2rtc/FFmpeg no firmware TIM desse roteador; não o tratar como ponte pronta. Sem outro equipamento confirmado, a alternativa sem nova compra é avaliar o PC existente ligado durante o uso. Um celular Android como ponte exigiria desenvolvimento e testes próprios, inclusive suspensão e conversão de codecs; não está entregue.
