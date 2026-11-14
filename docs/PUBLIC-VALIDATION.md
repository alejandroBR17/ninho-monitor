# Verificação da publicação pública

Código de portfólio preparado a partir do Android 2.5.0 (build 17) e da Ponte 1.4.0.

- 121 testes Flutter aprovados na cópia do código com os exemplos de rede fictícios.
- 24 testes Go aprovados com `go test -race ./...` na cópia pública da ponte.
- Inventário SHA-256 dos arquivos do código em SOURCE-SNAPSHOT.json conferido.
- Dados de execução, configurações reais, chaves de assinatura e credenciais excluídos do versionamento.
- Exemplos de IP e contato VAPID preparados para publicação, preservando identificadores de compatibilidade.
- O site privado de download e as aplicações instaladas não foram modificados por esta publicação.

Os testes foram executados em Linux. Não houve uma nova validação de hardware da câmera, bateria Windows, áudio real ou entrega push no iPhone. Consulte também bridge/VALIDACAO.md.


## Apresentação de portfólio

- Licença MIT escolhida pelo proprietário e reconhecida pelo GitHub.
- CI real em GitHub Actions com as suítes Flutter e Go aprovadas: https://github.com/alejandroBR17/ninho-monitor/actions/runs/43440652179 .
- Capturas reproduzíveis do visualizador executando com fonte RTSP sintética local, sem erros JavaScript; não houve conexão com uma câmera doméstica.
- A identidade visível do visualizador web foi ajustada para Ninho Monitor; dados protegidos, cookies, eventos internos, identificadores Android e comandos PTZ foram preservados. Não foi publicada uma atualização nos aparelhos ou na hospedagem privada.


## Atualização das imagens de demonstração

A apresentação usa uma cena doméstica fictícia gerada por IA, publicada por uma fonte RTSP de loopback e convertida pela ponte. O script de captura verifica avanço real do reprodutor, presença do vídeo e ausência de erros JavaScript. Nenhuma imagem doméstica foi usada. O histórico foi reduzido a um recorte de 440 px e está recolhido no README. O controle físico continua fora do escopo da demonstração.


## Marca e interface — Ponte 1.5.0

24 testes Go com detector de races aprovados. Reprodução, histórico, rotinas, filtros, desconexão, logout e tela cheia em retrato e paisagem verificados no Chromium com fonte sintética. A tipografia Manrope é local e os arquivos de licença OFL acompanham o código. Nenhum dado de produção foi usado nas capturas.

O site de download foi redesenhado com a mesma marca. Links, contraste, manifesto e reconstrução dos downloads foram verificados. A prévia gerenciada do Sites não estava disponível; a página hospedada não foi validada visualmente neste ambiente.


## Reconexão e diagnóstico — Ponte 1.5.1

Uma playlist existente deixou de ser tratada como vídeo ativo quando fica sem atualização por mais de 25 segundos. Conectar reaproveita o conversor saudável e substitui um processo travado; a preparação inicial mantém sua tolerância de tempo. Erros recebidos durante a conexão ficam pendentes para recuperação, em vez de serem ignorados. Uma pausa do sistema durante permissões deixa de ser confundida com o botão Pausar.

Copiar diagnóstico fica junto ao vídeo e no rodapé, inclusive sem login. Se a ponte não responder, o relatório inclui a última consulta com horário e até 40 eventos locais, sem senha, endereço, token ou assinatura push. Os eventos ficam apenas na memória da página; uma recarga limpa essa sequência. O teste de push tem prazo de rede maior que o prazo de envio no servidor.

Validação em Linux: 25 testes Go com detector de races; Chromium com RTSP sintético, mudanças de perfis/avisos, envio de teste recusado simulado, ocultar/retornar à página, pausa explícita preservada, erro durante conexão, playlist 404, cópia de diagnóstico offline e sem login, telas de 320/390/844 px. Um FFmpeg de teste foi suspenso de propósito: a ponte o substituiu e o vídeo voltou sem recarregar a aba. Não houve reprodução da falha no iPhone real nem confirmação de sua causa específica; entrega real de push, Windows/DPAPI e câmera física não foram validados neste reparo.


## Câmera desligada ou inacessível — Ponte 1.5.2

O diagnóstico conserva o erro de conexão da câmera separadamente da saída genérica do conversor. Informa se o conversor alcançou a ponte local, se a conexão TCP da câmera abriu, a última etapa RTSP e o código numérico de saída. Timeout, recusa e rede inacessível são classificados sem registrar endereço ou credenciais, incluindo os códigos Winsock. Respostas interrompidas ou malformadas têm códigos próprios. A primeira conexão manual também ganha até três novas tentativas; depois pede intervenção do usuário.

Testes Linux/Chromium com câmera sintética e porta local recusada verificam a preservação da causa após falha do conversor, o limite de tentativas e uma conexão bem-sucedida posterior. As verificações de notificações, visibilidade, pausa e diagnóstico offline da 1.5.1 foram repetidas. O diagnóstico enviado pelo usuário indicava falha antes de negociar RTSP; ele informou posteriormente que a câmera estava desligada. Não foi confirmada a causa da tentativa posterior à religação na câmera real, nem o IP atual.
