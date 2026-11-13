# Ninho Monitor — Ponte 1.4.0 — Windows x64

Ponte pessoal para câmera RTSP/ONVIF: notebook Windows → túnel HTTPS → Jortan Viewer Android ou visualizador Safari/Chrome. No iPhone, a página pode ser adicionada à Tela de Início; não exige app de câmera de terceiros nem IPA.

## Começar

1. Baixe o ZIP Windows no site privado do projeto. Clique com o botão direito e escolha Extrair tudo. Mantenha todos os arquivos juntos.
2. Execute INICIAR-PONTE.cmd. O executável abre o painel local no navegador. Se não abrir, copie o endereço de configuração mostrado na janela.
3. Informe o IP/usuário/senha local da câmera. Os padrões são IP 192.168.1.100, RTSP 554, ONVIF 5000, usuário admin, fluxo /onvif2. Use /onvif1 se quiser testar áudio; /onvif2 desta câmera não anunciou áudio.
4. Crie uma senha de acesso remoto com pelo menos 12 caracteres e salve. Nunca envie nenhuma dessas senhas pelo chat.
5. Copie o endereço HTTPS exibido no painel/janela. No iPhone, abra-o no Safari e entre com a senha REMOTA. Toque em Conectar vídeo e, se necessário, Reproduzir vídeo. Compartilhar → Adicionar à Tela de Início cria seu atalho Jortan.
6. No Jortan Viewer Android 2.5, abra a aba Remoto, cole esse mesmo endereço e toque em Abrir câmera remota. O visualizador abre dentro do aplicativo.

O notebook precisa ficar ligado, com a tampa aberta, ligado à tomada e conectado à rede da câmera. Enquanto aberta, a ponte solicita ao Windows manter o sistema ativo. Fechar a tampa pode suspender o notebook apesar disso. Feche a janela da ponte para encerrar o acesso. Não há instalação automática como serviço ou alteração permanente de energia/roteador.

## Endereço e privacidade

O endereço gratuito usa Cloudflare Quick Tunnel e pode mudar toda vez que a ponte reinicia. Nesse caso atualize a URL salva no Android e abra o novo endereço no Safari; um atalho antigo da Tela de Início também precisará ser atualizado. O túnel pode reconectar sozinho após perdas breves, mas não é um serviço com disponibilidade garantida. Para manter o endereço, use INICIAR-COM-ENDERECO-FIXO.cmd com o Tailscale já configurado; não é necessário comprar domínio.

A conexão HTTPS passa pelo serviço Cloudflare. Vídeo, playlist, segmentos e comandos exigem uma sessão autenticada na ponte. A senha de câmera fica no notebook, não aparece no endereço nem na linha de comando do FFmpeg. Ela é protegida no Windows com DPAPI do usuário; senha remota é armazenada como PBKDF2-SHA256 com salt. Arquivo local: %LOCALAPPDATA%/JortanBridge/config.bin. A configuração é reutilizada ao abrir de novo; não é preciso salvar outra vez. Para alterá-la, use o painel local e informe novamente as senhas.

A ponte escuta apenas 127.0.0.1. Não encaminha as portas 554/5000 nem muda o firewall. O painel de configuração exige host local e chave temporária. Cookies de sessão remota são Secure/HttpOnly/SameSite Strict; APIs de escrita exigem origem e CSRF; há limite de tentativas de login. Não há cache de vídeo no service worker. São mantidos segmentos temporários para transmissão, apagados ao encerrar/parar; não há gravação permanente planejada.

## Vídeo e controle

O notebook faz uma única conversão compartilhada para H.264 baseline 640×360/15 fps, AAC quando há áudio. Safari no iPhone usa HLS nativo; Chrome/Android usa hls.js quando disponível. Transmissão remota pode ter alguns segundos de atraso. Não há medida de atraso ponta a ponta ou áudio audível na câmera real. Após 90 s sem visualização o conversor para, exceto com monitoramento de movimento ativo; conectar novamente o reativa.

Conectar controle obtém perfil PTZ real e exige resposta de parada por ContinuousMove com velocidade zero. Depois escolha Setas ou Joystick. Velocidade solicitada 0,1 por eixo, timeout PT2S e limite 5 s por gesto. Soltar/cancelar/voltar ao centro pede parada. Sem heartbeat por 1,5 s, a ponte também pede parada; o limite do firmware continua importante. A chegada de comandos depende da conexão e uma resposta não mede movimento físico. Um comando por vez; só a última direção é renovada. Stop pendente não pode ser descartado por outro gesto; Parar de outra sessão autenticada pode interromper o controle. Um dispositivo de cada vez move a câmera.

## Requisitos, distribuição e validação

Windows 10/11 x64 Intel/AMD. Pacote portátil com JortanPonte.exe, ffmpeg.exe e cloudflared.exe. Não precisa instalar Python, Go, VLC nem usar conta Cloudflare para o túnel temporário. Executável Windows sem assinatura comercial; não alteramos proteções do Windows. Fonte, licenças e hashes dos componentes acompanham a entrega.

Testes executados em Linux: HTTP, autenticação/CSRF/sessões, proteção de mídia e painel, limite de login, RTSP Digest/normalização de transporte, interleaved sem corrupção e PTZ com interrupção automática. O mesmo código é compilado para Windows e PE x64 conferido, mas o binário Windows/DPAPI/túnel no notebook e Safari no iPhone ainda precisam ser executados pelo usuário. Há reprodução de câmera sintética no Chromium; não é prova de funcionamento na câmera real.

## Compilar

Go 1.26 ou superior (entrega compilada e testada com Go 1.27.4). Dependências fixadas em go.mod/go.sum: webpush-go 1.4.0, jwt/v5 5.3.1 e x/crypto 0.59.0, com licenças na pasta licenses. Web, hls.js e licenças são incorporados no executável.

```sh
go test -race ./...
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o JortanPonte.exe .
```

O build Linux é apenas para desenvolvimento; persistência fora do Windows usa arquivo 0600, não DPAPI. Não distribua essa edição como se fosse a versão Windows protegida. Leia AGENTS.md e DESIGN.md antes de alterar o produto.

## Atualização 1.0.1

Feche a ponte antiga, extraia o novo ZIP em outra pasta e execute INICIAR-PONTE.cmd. A configuração protegida existente é reutilizada. Use o novo endereço HTTPS mostrado. O app Android 2.4 não precisa ser reinstalado.

A preparação mostra a etapa atual e tem prazo de espera. Copiar diagnóstico informa versão, etapa RTSP, status, pacotes recebidos e quadros convertidos, sem senha, URL da câmera ou logs brutos. Falhas transitórias de HEVC não são tratadas isoladamente como causa comprovada. A ponte reconhece respostas RTSP precedidas de CRLF, preserva CSeq e reescreve URLs da própria câmera com porta padrão 554. O início do executável no Windows não bloqueia consultas de estado. A consulta inicial de sessão retorna estado anônimo sem erro; vídeo e comandos continuam protegidos.

## Interface 1.1.0

Login, visualizador e painel local refinados com a identidade do Jortan. Vídeo e controle lado a lado no computador e em uma coluna no celular; mostrar/ocultar senha no login; resolução efetivamente recebida; diagnóstico em seção recolhida. A versão Android 2.5 tem aba Remoto própria. O usuário confirmou funcionamento da ponte 1.0.1 na sua rede; esta atualização visual preserva o protocolo e limites de controle, sem nova confirmação física. Feche a ponte anterior, extraia o pacote e use o endereço HTTPS da nova execução.

## Retomada do vídeo — 1.1.1

A transmissão é mantida por uma renovação autenticada enquanto há vídeo em reprodução na aba visível, sem depender de cliques. Em segundo plano a página pausa e libera o reprodutor. Ao voltar, se estava assistindo, negocia novamente com a ponte e abre uma fonte HLS nova, mesmo que o conversor tenha sido encerrado por inatividade. Uma pausa feita pelo usuário continua sendo respeitada. Se a rede impedir reprodução automática, o botão Reproduzir permanece disponível.

Playlist ausente, erro de mídia ou vídeo sem avanço acionam até três tentativas de recuperação, com intervalos de 1, 3 e 6 segundos. A contagem é renovada após reprodução estável; sem conexão, Reconectar permanece utilizável sem recarregar a aba. Sair da conta cancela tentativas e sessão expirada exige novo login. Nenhum gesto PTZ é retomado automaticamente. Os 90 segundos sem pedidos de vídeo/renovação encerram o conversor quando o monitoramento está desativado. O Android 2.5 não precisa de novo APK para esta correção.

## Endereço fixo gratuito — 1.2.0

Instale o Tailscale apenas no notebook Windows, entre no plano Personal e abra INICIAR-COM-ENDERECO-FIXO.cmd. Se o painel pedir autorização do Funnel/HTTPS, use o botão que abre a conta oficial Tailscale. O endereço .ts.net apresentado pode ser aberto no Safari do iPhone e no Jortan Android sem Tailscale nesses aparelhos. A senha remota do Jortan continua obrigatória. A configuração da câmera é reutilizada e o Android 2.5 não precisa de novo APK. Veja ENDERECO-FIXO.md para os passos e limites.

O modo anterior continua em INICIAR-PONTE.cmd. O novo atalho executa `JortanPonte.exe --endereco-fixo`, consulta o Tailscale local, inicia Funnel em primeiro plano e mantém um listener loopback separado que bloqueia o painel e APIs locais. Configuração Funnel existente não é apagada/substituída; o processo é encerrado junto à ponte e a sessão temporária é retirada pelo daemon Tailscale. Não usamos --bg, reset, tokens no terminal nem login automático. Saída da CLI não é registrada: apenas estado, hostname público validado e eventual link de autorização acessível exclusivamente no painel local protegido são mantidos.

O endereço permanece estável enquanto os nomes/dispositivo da rede Tailscale forem mantidos. Funnel está em beta e tem limites de banda; plano pessoal gratuito não significa vídeo ilimitado. Fontes oficiais consultadas em 12/11/2026: https://tailscale.com/pricing e https://tailscale.com/docs/features/tailscale-funnel . A integração foi testada com CLI simulada; não foi ativada uma conta Tailscale real neste ambiente.

## Tela cheia e alertas — 1.3.0

Feche a ponte antiga, extraia a nova versão em outra pasta e execute INICIAR-COM-ENDERECO-FIXO.cmd para manter o endereço que já funcionou. A configuração existente é reutilizada. Não é necessário reinstalar o Android nem reconfigurar Tailscale.

No celular, o controle fica imediatamente abaixo da imagem. Tela cheia mantém vídeo e setas/joystick juntos; em retrato, gira a interface para paisagem. Inverter lado muda o sentido. Sair retorna ao layout normal. Essa rotação visual funciona como alternativa às limitações do Safari: não altera o bloqueio de orientação do iPhone. Pausar/retomar é uma ação explícita. O limite PTZ de 5 s e a parada ao soltar/cancelar continuam.

### Receber aviso com o visualizador fechado

1. No iPhone com iOS 16.4 ou superior, abra seu endereço HTTPS fixo no Safari. Use Compartilhar → Adicionar à Tela de Início e abra o Jortan pelo ícone criado.
2. Entre com a senha remota. Em Alertas de movimento, toque Ativar notificações neste aparelho e autorize no aviso do sistema.
3. Toque Enviar teste e confirme a chegada. Isso testa a assinatura push; não depende de movimento na câmera.
4. Ative o modo Dormir. Em Modos e automações, ajuste a sensibilidade, os avisos e o intervalo mínimo conforme o ambiente.
5. Mantenha notebook, ponte, Tailscale e conexão ligados. Com monitoramento ativo, a ponte mantém a conversão mesmo sem espectadores. O iPhone pode receber o aviso com a página fechada; permissões, Foco e conectividade do sistema podem afetar a entrega.

A detecção compara imagens no notebook, não consulta um sensor físico nem reconhece pessoas. Mudança uniforme de brilho é filtrada, mas luzes, ruído e giro podem causar alertas. Há aquecimento inicial, supressão breve após comandos PTZ e intervalo mínimo configurado no modo ativo (15 a 120 segundos na versão 1.4).

O monitoramento começa desativado. Quadros reduzidos são analisados em memória, sem fotos/gravações permanentes. O aviso contém texto genérico, sem imagem ou senha. O envio usa Web Push com mensagem criptografada e serviços do navegador (Apple/Google/Mozilla), sem cobrança ou conta adicional integrada. A análise usa a mesma transmissão da ponte, sem uma segunda conexão com a câmera.

A chave de envio, assinaturas dos aparelhos e preferência de monitoramento ficam em %LOCALAPPDATA%/JortanBridge/alerts.bin, protegido por DPAPI no Windows. Não distribua esse arquivo. Alterar a configuração da câmera/senha remota desativa monitoramento e redefine assinaturas: ative novamente nos aparelhos desejados. Desativar notificações neste aparelho remove apenas essa assinatura; desligar Monitorar a imagem no modo ativo interrompe a análise e os alertas de movimento para todos. Avisos do notebook têm preferência separada.

Testes sintéticos validam análise, criptografia e interface; a entrega em um iPhone real precisa ser confirmada com Enviar teste. Não há nova validação física de PTZ nesta atualização.

## Central da casa — 1.4.0

A atualização preserva câmera, senha remota, endereço fixo e assinaturas push existentes. Não precisa reinstalar o Android. Feche a ponte antiga, extraia o novo pacote e abra INICIAR-COM-ENDERECO-FIXO.cmd. Reabra o visualizador pelo mesmo endereço.

### Modos Casa, Fora e Dormir

Os botões acima do vídeo aplicam as preferências salvas para cada modo. Para novas instalações, Casa começa sem análise; Fora monitora em sensibilidade normal, com avisos a partir de 60 s entre eventos; Dormir monitora em sensibilidade alta, com intervalo mínimo de 15 s. Na atualização da 1.3, o modo Casa preserva o monitoramento e a sensibilidade que você já usava. Trocar de modo nunca gira a câmera.

Em Modos e automações, escolha o modo a editar e salve monitoramento, sensibilidade, avisos de movimento e intervalo mínimo de 15, 30, 60 ou 120 segundos. É possível registrar movimentos no histórico sem enviar notificação. O intervalo limita repetição; não é um prazo garantido de detecção ou entrega. Movimento na imagem não confirma que a bebê acordou. Luzes, roupas e giro podem gerar alertas, e movimentos pequenos podem não ser identificados. O Jortan não identifica sono, respiração ou condições de saúde.

### Histórico privado

Guarda até 300 eventos dos últimos sete dias: movimento, mudanças de modo, rotinas e avisos de energia/conexão. São somente códigos e horários, sem fotos, áudio ou clipes. O histórico pode ser filtrado e apagado na página autenticada. Ele fica no notebook em alerts.bin, protegido por DPAPI no Windows, junto às preferências. Alterar a configuração da câmera/senha remota redefine esses dados e as assinaturas; uma atualização normal do programa preserva tudo.

### Automações

Cadastre até oito rotinas diárias com horário e modo. Ative/desative ou remova cada rotina. Elas funcionam com o visualizador fechado e usam o relógio/fuso do notebook, exibido na página. Não há localização automática, rastreamento do usuário ou comandos físicos. O mesmo horário não pode ter duas rotinas ativas. Ao reiniciar, horários já perdidos não são executados retroativamente; uma rotina já aplicada naquele minuto não se repete. A ponte deve estar funcionando no horário da rotina.

### Notebook e continuidade do monitoramento

O Windows fornece energia, presença de bateria e carga; o sistema também verifica espaço disponível e chegada da imagem. A interface resume a situação sem CPU, memória ou outros números técnicos. A ponte verifica a cada 15 s e registra apenas mudanças: fora da tomada, bateria até 25%, bateria crítica até 10%, pouco espaço (menos de 512 MiB), perda prolongada de imagem e recuperação. Ligado à tomada é informação de alimentação confirmada pelo Windows; não estima autonomia nem comprova integridade do carregador.

A chegada da imagem é observada durante monitoramento ativo, com tolerância inicial de 45 s. A ponte tenta recuperar a transmissão. Avisos do notebook podem ser desativados separadamente dos avisos de movimento. Permissão push e teste de entrega continuam na seção Fique por perto; no iPhone use o ícone da Tela de Início com iOS 16.4 ou superior. Foco, permissões e conexão podem afetar ou atrasar a entrega.

Se o notebook desligar, suspender ou perder toda a internet, a própria ponte não consegue enviar notificação. A página aberta mostra Sem confirmação ao perder contato; não mantém um estado antigo de Tudo bem. Avisar sobre uma indisponibilidade total com o aplicativo fechado exigiria um monitor independente fora do notebook, ainda não incluído.

Testes automatizados e sintéticos estão em VALIDACAO.md. A leitura de bateria pela API do Windows e a entrega no iPhone precisam de confirmação nos aparelhos reais; não foram medidas neste ambiente Linux.
