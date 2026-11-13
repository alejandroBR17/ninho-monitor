# Testar a Jortan no VLC para iPhone

1. Instale o VLC media player, da VideoLAN: https://apps.apple.com/br/app/vlc-media-player/id650377962
2. Conecte o iPhone ao Wi-Fi da câmera. Permita o acesso à Rede Local quando o VLC solicitar.
3. Procure Fluxo de rede / Abrir fluxo de rede, na área Navegar/Explorar ou Rede (o nome varia conforme a versão).
4. Informe `rtsp://192.168.1.100:554/onvif1`.
5. Se pedir autenticação, use o usuário local `admin` e a senha local da câmera.

Se a versão do VLC não abrir o diálogo de autenticação, o formato alternativo é `rtsp://admin:SUA_SENHA@192.168.1.100:554/onvif1`. Substitua o espaço reservado só no próprio iPhone. Caracteres reservados na senha devem ser codificados na URL: @ → %40, # → %23, % → %25, / → %2F, ? → %3F, : → %3A. Não compartilhe o endereço contendo sua senha.

Este teste não exige um PC ligado. Requer acesso à mesma rede local. O app Android já validou /onvif1 com H.265 1920×1080 nesta câmera, mas a compatibilidade do motor do VLC com a resposta TCP inconsistente do firmware ainda precisa ser testada. Se falhar, anote a mensagem exata, sem senha, para investigar. Não foi entregue um IPA do Jortan Viewer.

Fontes oficiais:
- https://apps.apple.com/br/app/vlc-media-player/id650377962
- https://images.videolan.org/vlc/download-ios.html
- https://docs.videolan.me/vlc-ios-user/gettingstarted/media_synchronization.html
