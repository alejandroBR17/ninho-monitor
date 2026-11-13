# Diretrizes de interface — Jortan Viewer

Preferência persistida a pedido do usuário em 05/11/2026. Aplica-se ao aplicativo e ao site de download. Referência visual: checklist de UI de Cleilton Rocha, @cleiltonrocha.dev, enviado pelo usuário.

## Regras para cada atualização

1. Texto com contraste mínimo de 4,5:1 sobre o fundo real. Estados desabilitados devem continuar reconhecíveis e não depender apenas de cor. Verificar também ajuda, legendas, erros e campos.
2. Espaçamentos de layout na escala 8, 16, 24 e 32 pixels (dp no Flutter). Fontes, ícones, bordas e proporções de vídeo não são unidades de espaçamento. Evitar valores arbitrários de margens, padding e gaps.
3. No máximo dois pesos de fonte: regular 400 e semibold 600. Manter hierarquia por tamanho e espaçamento.
4. Botões com altura mínima de 48 px/dp; alvos interativos de pelo menos 44 px/dp. Não encolher a área de toque de ícones, chips, links ou botões secundários.
5. Uma ação primária por tela/etapa. Conectar na tela ao vivo, salvar/testar nas configurações, compartilhar no diagnóstico e baixar/salvar no site. Ações secundárias devem ser visualmente secundárias.
6. Não usar texto em gradiente nem badges com borda.

## Aplicação ao produto

- Priorizar celular; manter layout utilizável na horizontal, no PC e com texto ampliado.
- Paleta escura verde: fundo #101B1C, superfícies #172526 / #1C2C2D, texto #F2F7F5, secundário #B8C9C6 e destaque #77E2C2. Botão principal com texto #09221B.
- Evitar informação técnica na ação cotidiana. Mensagens simples na tela e detalhes completos em Diagnóstico.
- Mostrar erro, carregamento, ausência de suporte e sucesso como estados diferentes. Uma falha de consulta não comprova que a câmera não tenha PTZ.
- Manter instruções de segurar/soltar, parada por gesto cancelado e estado habilitado dos controles. Nunca habilitar movimento baseado em capacidades inventadas.
- Verificar contraste calculado, áreas de toque, pesos de fonte e layout vertical/horizontal antes de distribuir. Testes simulados não substituem validação física da câmera nem escuta real do áudio.

## Persistência

Este arquivo e os AGENTS.md do app e do site fazem parte do projeto e do código-fonte entregue. Atualizações futuras devem consultar este guia. Isso preserva a preferência nos arquivos do projeto; não depende de promessa de memória global fora dele.


## Teste manual solicitado na versão 2.0

Em 06/11/2026, o usuário pediu explicitamente incluir um modo experimental Yoosee com ativação manual, toque curto e Parar, sem depender das consultas de capacidades recusadas. Depois confirmou movimento no Onvier e pediu continuidade enquanto segura a seta, como no Yoosee original. Não apresentar velocidades/limites solicitados pelo driver como capacidades consultadas da câmera. Manter descoberta sem movimento, exigir confirmação de uma operação de parada: Stop ou ContinuousMove com PanTilt em velocidade zero, equivalente definido no ONVIF. Iniciar com toque curto de até 300 ms e velocidade solicitada de 0,1. Oferecer opção explícita Segurar para mover: renovação sem fila de movimentos, timeout solicitado de 2 s na câmera e máximo de 5 s por pressão. Soltar/cancelar envia parada após o movimento em andamento. Desativar teste ao sair da tela/app ou após erro. Resposta SOAP não comprova movimento físico nem obediência à parada/timeout. Não habilitar zoom físico por suposição. Tooltip não deve capturar a pressão longa e cancelar o gesto da seta.


## Uso diário a partir da 2.2

Em 06/11/2026, depois de confirmar movimento físico na 2.1 (com pausas), o usuário solicitou retirar as etapas de teste e entregar a versão de uso diário. O fluxo normal prepara automaticamente o controle com vídeo conectado, prioriza o formato ONVIF padrão e parada por velocidade zero que receberam resposta válida, guarda perfil/endpoint/formato em armazenamento protegido e reconfirma a parada ao reconectar. A preparação nunca solicita movimento. Segurar para mover passa a ser o padrão, mantendo 0,1, PT2S e limite local de 5 s; o painel informa esse limite. Sair/cancelar para o movimento; voltar prepara novamente sem pedir ativação manual. Erro não libera setas; oferece reconexão. Não apresentar capacidades como consultadas quando não foram nem afirmar detecção automática de giro. A confirmação física do usuário é evidência da versão 2.1 nesta unidade, não garantia universal ou de fluidez. Histórico de telas experimentais e testes de regressão pode permanecer no código, fora do fluxo normal do produto.


## Joystick e ações de vídeo — 2.3

Solicitados pelo usuário em 06/11/2026: distinguir tela cheia de redefinir zoom, oferecer joystick como alternativa às setas e otimizar o app. Manter apenas o ícone de tela cheia para entrar/sair; Redefinir zoom deve ser texto explícito com ícone de reinício e desabilitado quando a imagem já está no tamanho original. Joystick é opção persistida, sem substituir obrigatoriamente as setas. Zona central para parada, cancelamento/soltura/Parar/inatividade encerram gesto; limite de 5 s por gesto não reinicia ao mudar direção. Enviar apenas a direção mais recente, sem fila de posições nem aumento da velocidade 0,1 por eixo. Manter controles individuais como alternativa acessível. Não prometer fluidez ou redução medida de CPU/latência sem medição real.


## Acesso remoto com ponte Windows — 2.4

Em 12/11/2026, o usuário passou a manter o notebook Windows e pediu assistir pelo app e pelo navegador próprio, inclusive no iPhone sem outro app de câmera. Preservar uso local e adicionar acesso remoto por HTTPS, sem credenciais na URL. A ponte serve o visualizador e converte HEVC/G.711 para H.264/AAC compatível com navegador. Configuração de credenciais deve ocorrer localmente no notebook, com senha remota separada e dados protegidos via DPAPI; vídeo e comandos remotos exigem login. O túnel gratuito gera endereço que pode mudar ao reiniciar; isso deve aparecer nas instruções. No iPhone oferecer Safari e Tela de Início, sem afirmar que foi entregue IPA. Preservar limite PTZ de 5 s, parada no cancelamento/soltura, perda de heartbeat e confirmação prévia de parada. Não afirmar validação em Windows/câmera/iPhone reais quando os testes foram sintéticos e no Linux.


## Refinamento visual — 2.5 / Ponte 1.1

Solicitado em 12/11/2026 após o usuário confirmar funcionamento remoto. Dar prioridade ao vídeo e separar o acesso Remoto em destino próprio no Android. Recolher imagem/som e diagnósticos fora da ação principal; preservar parâmetros e limites do controle. Na web usar duas colunas no computador e uma no celular, com autenticação, estado vazio, conexão e erro distintos. Manter identidade verde escura, ícones coerentes, espaço e tipografia sem sobrecarregar o uso diário. Não apresentar conexão ativa antes de a reprodução começar. Melhorias visuais não comprovam menor latência nem novos testes físicos.


## iPhone e alertas — Ponte 1.3

Solicitado pelo usuário: controles próximos à imagem e tela cheia em paisagem mesmo com retrato bloqueado. Usar rotação visual da interface como alternativa às limitações do Safari, sem afirmar mudança do bloqueio do iOS. Manter vídeo e controles juntos e permitir sair/inverter lado; cancelar gestos durante mudanças de layout. Alertas com visualizador fechado foram solicitados explicitamente: usar Web Push com adesão manual pela Tela de Início, nunca pedir permissão automaticamente. Descrever detecção como análise da imagem no notebook, desativada por padrão, com intervalo entre eventos e possíveis falsos positivos. Não afirmar entrega real no iPhone sem teste no aparelho. Preservar autenticação, privacidade e limites PTZ.


## Central da casa — Ponte 1.4

O usuário aprovou histórico de eventos, modos Casa/Fora/Dormir, automações e avisos simples do notebook para acompanhar a bebê dormindo. Manter vídeo e controles em primeiro plano; modos resumidos acima, detalhes de ajustes recolhidos. Histórico de metadados autenticado, limitado e apagável, sem gravação ou fotos implícitas. Movimento não confirma que a bebê acordou; não inferir sono, respiração ou saúde. Avisos de tomada/bateria/chegada da imagem devem distinguir atenção, recuperação e estado desconhecido, sem informações técnicas no uso diário. Não manter Tudo bem após perda de contato. Explicar que desligamento/internet indisponível impede a própria ponte de enviar push. Automações de horário são explícitas, no relógio do notebook, sem movimento físico ou localização automática. Preservar preferências e assinaturas nas atualizações.
