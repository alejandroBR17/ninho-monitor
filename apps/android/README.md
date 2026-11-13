# Ninho Monitor — Android

Aplicativo de uso diário para assistir e mover a câmera Jortan/Yoosee na rede Wi-Fi local. Edição Android compilada em modo release, com a mesma assinatura das versões instaladas. Independente dos fabricantes.

## Instalar e usar

1. Baixe o APK ARM64 no site privado do projeto e instale por cima da versão anterior. A configuração e a senha são preservadas.
2. Abra o app na rede Wi-Fi da câmera e toque em **Conectar à câmera**. Se ainda não houver configuração, use **Configurar minha câmera** e a senha local RTSP/ONVIF.
3. O painel prepara o controle automaticamente. **Escolha Setas ou Joystick**. Segure uma seta ou arraste o joystick para mover; solte ou volte ao centro para parar. Sua escolha fica salva. Cada pressão tem limite de 5 segundos. O botão Parar permanece disponível.
4. **Mais detalhes** usa /onvif1 e **Mais fluido** usa /onvif2. Este último não anunciou áudio na câmera testada. Compartilhar imagem abre o menu do celular com um quadro PNG.
5. Em caso de falha, use **Reconectar controle**; o diagnóstico curto e o arquivo completo continuam disponíveis.

Não é mais necessário escolher um modo experimental, ativar teste ou ligar Segurar para mover em cada sessão. Depois da primeira preparação, o perfil, serviço e formato aceitos são guardados no armazenamento protegido do celular. Ao reconectar, a parada é confirmada novamente antes de liberar as setas. Se a configuração salva deixar de funcionar, o app busca os perfis atuais. Nenhum movimento é enviado durante a preparação.

## Compatibilidade e evidências

- Android 7/API 24 ou superior, ARM64. RTSP TCP/UDP; ponte de compatibilidade TCP opera apenas no próprio celular.
- Vídeo real confirmado pelo usuário: /onvif1 HEVC 1920×1080 e /onvif2 HEVC 640×360. /onvif1 anuncia PCMA/16000; /onvif2 anuncia apenas vídeo. Sincronia audível e latência ponta a ponta não foram medidas.
- Movimento físico no Jortan 2.1 confirmado pelo usuário, com pausas. A câmera aceitou ContinuousMove e parada por velocidade zero no serviço PTZ anunciado; consultas de opções e Stop convencional falharam. O controle de uso diário conserva esse protocolo e seus limites.
- A câmera pode responder com atraso e ainda apresentar pausas. Resposta SOAP não é detecção automática de movimento físico. A nova preparação automática e o pacote release da 2.2 ainda precisam de uso no aparelho real.
- Sem gravação de vídeo, microfone/retorno de áudio, nuvem Yoosee ou acesso WAN configurado. Zoom físico não é oferecido por suposição; o zoom de imagem é digital.

## Privacidade e distribuição

Senha RTSP/ONVIF no armazenamento protegido, sem backup Android. Diagnósticos removem credenciais; ainda contêm IPs e parâmetros técnicos. Preferências de controle ficam protegidas e restritas à mesma câmera/usuário/URL ONVIF. Site de download permanece privado. Chaves de assinatura e credenciais não integram o ZIP do código-fonte.

O APK release conserva o certificado existente para permitir atualização direta. É distribuição pessoal pelo site privado; publicação em loja exigiria planejamento próprio de assinatura. Não altere a assinatura de atualizações existentes.

## Desenvolvimento

Flutter 3.47.9, Dart 3.13.7, JDK 21, SDK 36, NDK 28.2.13676358; dependências fixadas em pubspec.lock.

```sh
flutter pub get
flutter analyze
flutter test --concurrency=2
flutter build apk --release --target-platform android-arm64
```

Saída: build/app/outputs/flutter-apk/app-release.apk. O build release usa AOT e não habilita depuração Android. Assinatura deve ser conferida com apksigner antes de distribuir. Leia AGENTS.md e docs/DESIGN.md antes de alterar interface. Veja docs/JOYSTICK.md, docs/USO-DIARIO.md e docs/VALIDACAO.md; evolução anterior em docs/HISTORICO.md.

## iOS

O projeto iOS compartilhado permanece no código-fonte. Não há IPA: compilar, assinar e distribuir para iPhone requer Mac/Xcode e assinatura Apple, indisponíveis neste ambiente Linux. O VLC no iPhone foi confirmado anteriormente pelo usuário; ele não equivale a um build iOS deste app.

## Novidades da 2.3.0

- Tela cheia mantém um único botão de expansão, com ícone de saída quando expandida. O segundo ícone parecido era redefinição de zoom; agora aparece como Redefinir zoom, com ícone de reinício e habilitado apenas se houver zoom aplicado.
- Joystick de oito direções, zona central neutra, parada ao soltar/cancelar/pressionar Parar, preferência persistida e limite de 5 segundos por gesto. Setas continuam disponíveis. Velocidade e protocolo aceitos pela câmera são preservados.
- Renovação PTZ programada ao concluir a resposta, descontando o tempo já transcorrido, sem temporizador periódico aguardando rede. Apenas a última direção é enviada. Elimina esperas extras de até um ciclo do agendador; o ganho físico ainda precisa ser observado na câmera. Atualizações repetidas de disponibilidade de áudio não redesenham a página, e a expressão usada para filtrar logs é reutilizada.
- Não foram alterados codecs, buffers/probe HEVC, transporte ou volume para tentar ganhar fluidez. Não houve medida nova de FPS, consumo de CPU ou latência ponta a ponta.

## Acesso de longe — 2.4.0

A edição Android inclui Acesso de longe: salve a URL HTTPS gerada pela ponte Windows e abra o visualizador dentro do app. A câmera local continua com os mesmos controles e protocolo. No iPhone não há IPA; use o visualizador próprio no Safari ou adicione-o à Tela de Início. A ponte e o guia estão no mesmo download privado. Credenciais de câmera são informadas só no notebook, nunca na URL ou no chat. O endereço gratuito pode mudar ao reiniciar a ponte. Veja a documentação do projeto jortan_bridge.

## Interface 2.5.0

Acesso local e remoto em destinos separados; imagem e som recolhidos em preferências; navegação, tipografia e cores alinhadas ao visualizador web. O acesso remoto mantém o endereço protegido já salvo. A configuração local, protocolo RTSP, controle, velocidade e limites de gesto foram preservados. Instale por cima da versão anterior para manter os dados e a assinatura.
