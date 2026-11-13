# Estudo de caso · Ninho Monitor

## Contexto

O ponto de partida foi uma câmera doméstica já disponível. O objetivo era manter o acesso local no Android e assistir remotamente pelo navegador do iPhone, com um visualizador próprio. O notebook Windows passou a atuar como ponte entre a rede da câmera e os clientes remotos.

Isso exigiu lidar com um equipamento que implementa os protocolos de forma parcial: responder a uma consulta ONVIF não significa implementar todas as operações PTZ, e receber uma resposta HTTP não confirma movimento físico.

## 1. Primeiro, separar evidência de hipótese

O diagnóstico passou a distinguir controle RTSP conectado, autenticação confirmada, pacotes recebidos e quadros efetivamente convertidos. Erros de rede, falhas SOAP e ausência de áudio têm estados diferentes. Credenciais e cabeçalhos sensíveis são removidos dos relatórios.

A implementação evita atribuir ausência de vídeo automaticamente a firewall ou tratar uma consulta ONVIF recusada como prova de que não há controle de movimento.

## 2. Compatibilidade sem reescrever tudo

O firmware podia responder a SETUP com `RTP/AVP` e canais interleaved, omitindo `/TCP`. A ponte normaliza apenas esse caso, quando os canais correspondem ao pedido. O tráfego RTP continua sendo encaminhado sem alterar seus dados.

Essa restrição é importante: corrigir um campo conhecido é diferente de presumir suporte a qualquer transporte. Os testes também cobrem respostas com CRLF inicial, correlação CSeq, autenticação e preservação de pacotes.

**Código:** [rtsp.go](../bridge/rtsp.go), [rtsp_test.go](../bridge/rtsp_test.go), [fixes_test.go](../bridge/fixes_test.go).

## 3. Controle de movimento com limites explícitos

As consultas de capacidades podiam falhar mesmo com comandos de movimento aceitos. O fluxo prepara o controle por operações de parada e pelos perfis efetivamente retornados. Para o firmware acompanhado, a parada por velocidade zero foi necessária como alternativa à operação Stop.

Durante um gesto, só a direção mais recente importa. Não existe uma fila de posições antigas para executar depois. Soltar, cancelar, perder heartbeat ou atingir o limite local encerra o gesto. Uma resposta aceita continua não sendo prova de movimento físico nem de obediência do motor ao timeout.

**Código:** [motion.go](../bridge/motion.go), [motion_test.go](../bridge/motion_test.go), [ptz_motion.dart](../apps/android/lib/ptz_motion.dart).

## 4. Escolher interoperabilidade no acesso remoto

A câmera podia entregar HEVC e G.711. A ponte converte para H.264/AAC e publica HLS, que pode ser reproduzido pela PWA. Uma conversão é compartilhada entre espectadores, em vez de abrir um conversor por aba.

Essa escolha simplifica a compatibilidade com navegadores, ao custo de processamento no notebook e atraso adicional. WebRTC não foi implementado; não há promessa de latência mínima.

**Código:** [stream.go](../bridge/stream.go), [app.js](../bridge/web/app.js).

## 5. Tratar o retorno do segundo plano como reconexão

Uma playlist temporária pode desaparecer quando o conversor expira. O cliente mantém uma renovação enquanto a página está visível e reproduzindo, libera a reprodução em segundo plano e renegocia a fonte ao voltar. Uma pausa feita pelo usuário é respeitada.

A recuperação tem número limitado de tentativas e deixa uma ação explícita de reconexão. Nenhum movimento de câmera é retomado automaticamente.

**Código:** [viewer_lifecycle_test.go](../bridge/viewer_lifecycle_test.go), [app.js](../bridge/web/app.js).

## 6. Monitorar sem depender da aba aberta

A análise de imagem, os modos e as rotinas são executados no notebook. A interface configura o comportamento e consulta seu estado; não precisa ficar aberta para que uma rotina seja aplicada. O histórico tem retenção e limite de tamanho, e não armazena fotos ou clipes.

A leitura de energia usa a API nativa do Windows. Estados desconhecidos não viram automaticamente Tudo bem. A limitação restante é explícita: a ponte não pode avisar se ela própria estiver desligada ou sem conexão. Isso exige um monitor externo, ainda no roadmap.

**Código:** [alerts.go](../bridge/alerts.go), [home.go](../bridge/home.go), [health_windows.go](../bridge/health_windows.go).

## Resultado e verificação

O código publicado reúne Android, ponte Windows, visualizador web, eventos e automações. A preparação pública passou por 121 testes Flutter e 24 testes Go com detector de races. As capturas do README usam uma fonte RTSP sintética.

Essa evidência sustenta o comportamento coberto pelos testes. Ela não mede desempenho no notebook do usuário nem comprova entrega push ou movimento físico na câmera real. O projeto não publica métricas de latência ou cobertura que não foram medidas.
