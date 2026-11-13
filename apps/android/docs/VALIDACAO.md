# Validação

## Executado neste ambiente

- `flutter analyze`: sem problemas.
- `flutter test`: 97 testes de configuração, armazenamento (com implementação simulada), interface e ciclo da conexão (com reprodutor simulado).
- Cobertura: credenciais com caracteres reservados; configuração inválida; relatórios sem senha e JSON válido; espera do primeiro quadro; fallback TCP → UDP com encerramento anterior; cancelamento; limite de três reconexões; vídeo parado; formulário; layout vertical/horizontal.
- Prova técnica com `media_kit` e libmpv 0.40.0 no Linux: vídeo H.264 640×360 decodificado, com reprodução avançando, tanto por TCP quanto por UDP. O probe usa as mesmas opções RTSP do app e saída de vídeo nula; não valida a renderização no celular.
- Fonte sintética MediaMTX 1.21.3 e FFmpeg: recepção/decodificação de quadros H.264 por TCP e UDP no Linux. Isso valida a fonte de teste, não substitui executar o app num celular.

- APK Android debug gerado com sucesso; assinatura de desenvolvimento verificada por `apksigner`. Identidade do app e SDK mínimo 24 conferidos com `aapt`.

## Teste do reprodutor nativo em aparelho

Requer Flutter, um Android/iPhone conectado e MediaMTX + FFmpeg em um computador de desenvolvimento. Esse computador só é necessário para esta fonte de teste; no uso real, a câmera faz esse papel.

```sh
python3 scripts/rtsp_fixture.py
flutter test integration_test/rtsp_test.dart -d ID_DO_APARELHO --dart-define=RTSP_HOST=IP_DO_COMPUTADOR
```

Use uma rede privada de teste e permita TCP 8554 e UDP 8000/8001 entre o aparelho e a fonte. A fonte usa credenciais sintéticas públicas (`viewer` / `test-only`). Não reutilize senhas reais nela. Encerre com Ctrl+C depois do teste. Em emulador Android, o host padrão é `10.0.2.2`.

A integração testa primeiro quadro renderizado por TCP/UDP e rejeição de senha/caminho. **Não executada aqui: não há emulador Android nem aparelho físico conectado.**

## Aceitação na Jortan real — pendente

1. Instalar o APK, configurar as credenciais dentro do app e confirmar vídeo com o PC desligado.
2. Manter reprodução por pelo menos cinco minutos. Observar atrasos, codec e estabilidade.
3. Testar TCP e UDP manualmente e registrar o resultado real de cada transporte.
4. Desligar temporariamente a câmera e verificar reconexão, limite de tentativas e cancelamento.
5. Colocar o app em segundo plano e verificar que a reprodução para; ao voltar, reconectar manualmente.
6. Reiniciar o app e verificar a recuperação dos dados protegidos. Testar “Esquecer câmera”.
7. Girar o aparelho, abrir/fechar tela cheia e verificar a opção de manter a tela ligada.
8. Exportar o relatório e conferir que nenhuma credencial aparece.

## iOS — pendente

Compilação no macOS, assinatura, instalação, prompt de Rede Local, Keychain, TCP/UDP, comportamento em segundo plano e reprodução real. Não considerar o suporte iOS validado antes dessas etapas.


## Atualização 1.1.0

- Regressões do relatório real TCP/UDP: “property not found” não gera diagnóstico de caminho inválido; CSeq é indício, e falha de formato mantém causa indeterminada.
- Servidor RTSP local de teste: cabeçalhos fragmentados, CSeq 0, desafio Digest, SDP H.264, timeout, cancelamento e respostas grandes.
- Autenticação Digest comparada com vetor independente; Basic e remoção de tokens verificados.
- Teste direto autenticado e SDP contra MediaMTX, seguido de vídeo 640×360 por TCP e UDP no motor nativo Linux: aprovado.
- APK 1.1.0/build 2 gerado e assinatura comparada com a versão anterior: igual.
- Compilação/análise sem erros. Reprodução e compartilhamento na versão Android 1.1.0 com a Jortan real: ainda pendentes de teste no aparelho do usuário. iOS continua sem compilação/validação neste ambiente.


## Atualização 1.2.0

- 45 testes automatizados aprovados; análise estática sem problemas.
- Simulador reproduziu `Nonmatching transport in server reply` sem a ponte.
- Com a ponte, o motor libmpv no Linux decodificou vídeo 640×360, registrando uma correção e chegada de RTP.
- Fonte RTSP normal decodificada com zero correções.
- Testes de fragmentação RTSP/RTP, integridade de bytes binários, Digest recalculado, recusa de alterações em UDP/canais divergentes e classificação específica do erro.
- Build 3/versionName 1.2.0 conferidos no APK; certificado igual ao 1.1.0.
- Reprodução na Jortan real/Android e iOS: ainda não validadas nesta versão.


## Atualização 1.3.0

- 45 testes Flutter aprovados e análise estática sem problemas.
- CIDR privado, limite de hosts/concorrência, cancelamento, correlação de mensagens ONVIF, XML inválido e distinção RTSP/HTTP verificados.
- Sockets locais reais testam resposta RTSP 401 sem envio de Authorization, rejeição de HTTP e timeout limitado.
- Interface de busca testada: resultado selecionável devolve IP/porta; layout iPhone informa Rede Local e rejeita faixa pública.
- APK 1.3.0/build 4 gerado; assinatura comparada com 1.2.0 e preservada.
- O usuário confirmou vídeo real na Jortan com a versão 1.2.0: estado live, H.265 1920×1080, decodificação por hardware e correção TCP aplicada.
- Busca na rede física do usuário e VLC no iPhone ainda não testados. iOS nativo não compilado/assinado neste Linux.


## Atualização 1.4.0

- 56 testes Flutter aprovados; análise estática sem problemas.
- Servidor HTTP/SOAP local valida GetCapabilities, GetProfiles, GetConfigurationOptions, UsernameToken SHA-1 com nonce/Created, HTTP Digest com método POST/caminho correto, movimentos com limites anunciados e Stop.
- Testados: rejeição de endpoint externo/credenciais na URL, falha SOAP NotAuthorized sem exportar texto sensível, timeout de rede e migração da configuração antiga.
- Testados: parada após movimento pendente, cancelamento/liberação do gesto, desabilitação do botão, limite de pressão de 5 segundos e parada após falha do comando.
- Testado ciclo de áudio simulado: inicia silenciado, alterna escuta e erro de áudio não encerra vídeo.
- Fonte RTSP sintética H.264 640×360 + PCMA 16 kHz decodificada no libmpv Linux, com áudio/vídeo negociados pela ponte. Fonte normal: zero correções; resposta SETUP malformada: duas correções (vídeo e áudio). Propriedade nativa de volume conferida ao ativar/silenciar, com saída de áudio nula. Não comprova som no alto-falante Android.
- APK Android 1.4.0/build 5 gerado; apksigner e aapt confirmaram identidade, SDK mínimo 24 e mesmo certificado SHA-256 da versão anterior.
- Pendente na Jortan real: serviço ONVIF/porta, credenciais ONVIF, capacidades PTZ, zoom contínuo, respeito a Stop/Timeout, áudio audível, regressão do vídeo e gestos de zoom digital. Não se afirma controle físico com base em testes simulados.
- iOS permanece sem build/assinatura/teste físico; nenhum IPA entregue.


## Atualização 1.5.0

- 65 testes Flutter aprovados; flutter analyze sem problemas. Captura opcional de interface aprovada e telas iniciais/configuração inspecionadas visualmente no renderizador Flutter.
- Testado servidor HTTP que exige Content-Length UTF-8 correto, ausência de Transfer-Encoding chunked, Connection: close e SOAPAction.
- Regressão do relatório: GetCapabilities/GetProfiles funcionam e GetConfigurationOptions encerra a conexão; a consulta se recupera por GetNode correlacionado. Outra prova cobre porta PTZ anunciada errada versus porta ONVIF confirmada.
- Testado: consultas PTZ falhas mantêm capacidades indeterminadas; espaços de outro nó não habilitam o perfil; ContinuousMove com resposta perdida não é repetido; inspeção não envia movimentos.
- Regressão RTSP: buffer conserva 401 mas perde 200; status fora do buffer impede diagnóstico falso de senha e identifica HEVC sem dimensões. Avisos repetidos não eliminam o erro terminal da lista importante.
- Contraste calculado para textos primário/secundário/destaque/erro em todas as superfícies do tema (mínimo 4,5:1); pesos 400/600, botões mínimos 48 e badges sem borda conferidos. O CSS do site aplica os mesmos tokens e alvos de 44/48. Browser QA do site não disponível neste ambiente; mecanismo JS de download validado por reconstrução/SHA-256.
- Fonte RTSP sintética H.264 640×360 + PCMA 16 kHz novamente decodificada no libmpv Linux com análise de 10 segundos: duas correções no SETUP malformado e zero na fonte normal. Volume nativo conferido para ativar/silenciar; saída de áudio nula, sem comprovação de som físico.
- APK Android 1.5.0/build 6 gerado; versão, identidade e certificado SHA-256 iguais às atualizações anteriores (mesma assinatura), com SDK mínimo 24.
- Usuário confirmou no relatório 1.4: vídeo HEVC 1920×1080 ao vivo por UDP e parâmetros de áudio 16 kHz; ONVIF respondeu na porta 5000 e retornou perfis. TCP não recebeu parâmetros suficientes antes de abrir o codec.
- Pendente: recompilar/assinar/testar iOS e validar a versão 1.5 na Jortan real, especialmente endpoints PTZ, comandos físicos, Stop/Timeout, áudio audível e início do TCP. Não se afirma que o controle físico foi consertado apenas com simulação.


## Atualização 1.6.0

- 70 testes Flutter aprovados e análise estática sem problemas.
- Teste que reproduz o padrão de endpoints do relatório: Media anunciado como ptz_service, PTZ como deviceio_service; GetServices identifica os tipos por namespace e o app usa o endpoint correto confirmado por resposta.
- Teste com GetServices não suportado e dispositivo encerrando a conexão nos caminhos anteriores: a consulta de leitura em /onvif/ptz_service confirma as opções. Inspeção não envia ContinuousMove.
- Testes de cache por consulta: GetNode/GetNodes falhos idênticos não são repetidos para cada perfil. Resultados de outro nó não habilitam o perfil.
- Teste impede envio de credenciais para endpoint GetServices fora do IP configurado.
- Regressão do erro agregado: timeout na porta 5000 prevalece sobre recusas rápidas em outras portas.
- APK Android 1.6.0/build 7 gerado; identidade, SDK mínimo 24 e mesmo certificado SHA-256 de assinatura verificados. O fluxo nativo não foi alterado nesta atualização; não foi necessário repetir a prova sintética de reprodução feita na 1.5.
- Evidência do usuário na 1.5: vídeo TCP HEVC 1920×1080 ao vivo, parâmetros de áudio 16 kHz e ausência de erro fatal na sessão. A escuta estava desativada no relatório; não se afirma áudio audível.
- Pendente: testar controle real da versão 1.6, verificar endpoints/serviços desse firmware e confirmar respeito aos comandos Stop/Timeout. iOS próprio ainda não compilado/assinado; VLC no iPhone foi confirmado pelo usuário, sem equivaler à validação do nosso app ou do Safari.


## Atualização 1.7.0

- 86 testes Flutter aprovados; análise estática sem problemas. Após ajustes finais dos contadores/prefixo, os 9 testes específicos de perfis, GetServices e bloqueio manual PTZ foram repetidos e aprovados.
- Testes cobrem migração/persistência da preferência, preservação das credenciais e endpoints, caminho personalizado, escolha explícita do fluxo alternativo, resolução informada somente depois de recebida, ação de atualizar e layout com texto ampliado em 360 dp.
- Testado GetServices com contêiner alternativo, atributos e namespace com barra final, incluindo remoção da senha de um campo de resposta antes de reter o resumo.
- Testado: espaço genérico explicitamente declarado habilita apenas perfil de teste manual; espaço vendor não habilita; inspeção não move; botão permanece desabilitado até a ativação manual. Parar força Stop mesmo quando o controlador está ocioso.
- Prova nativa libmpv/Linux: fluxo principal sintético 640×360 e fluxo alternativo 320×180, PCMA/16000, início com aid=no, ativação do áudio e retorno a aid=no/volume zero conferidos. Fluxo normal: zero correções; alternativo via simulador de cabeçalho SETUP malformado: duas correções. Nenhuma dessas dimensões descreve a câmera real.
- O teste nativo aguarda posição avançar e parâmetros de vídeo disponíveis para evitar confundir atraso de eventos assíncronos com falha de decodificação.
- Capturas da interface inicial, configuração e preferências de imagem aprovadas e inspecionadas no renderizador Flutter.
- APK Android 1.7.0/build 8 gerado; aapt e apksigner confirmam versão, mínimo API 24, identidade e mesma assinatura anterior.
- Pendente: resolução/caminho alternativo da Jortan, efeito real sobre atraso e áudio, interpretação dos serviços reais e movimento/Stop/Timeout no firmware. Não foi medida latência ponta a ponta nem validado controle físico. iOS próprio continua sem build/assinatura; VLC no iPhone foi confirmado pelo usuário.


## Versão 1.8.0

- Analyze sem problemas; 84 testes aprovados. Regressões novas: SOAP 1.1 com HTTP 200 e códigos conhecidos/desconhecidos, SOAP 1.2 com motivo e senha removida, detail sensível não exportado, disponibilidade de áudio por fluxo e reinicialização entre sessões. O teste RTSP também confere SDP sem áudio.
- Relatório real 1.7: troca para /onvif2 confirmada pelo usuário, vídeo 640×360 e SDP sem áudio. O principal já entregou 1920×1080 e anunciou PCMA/16000 nos relatórios anteriores.
- GetConfigurationOptions retornou SOAPFault; o código e motivo específicos do novo parser ainda precisam de relatório da câmera real. Nenhum teste físico de movimento foi executado neste ambiente. Não se habilitam movimentos por capacidades inventadas.
- Assinatura Android e versão conferidas antes de distribuir; guia de design incluído no ZIP. Áudio audível/sincronização e funcionamento iOS próprio continuam pendentes.


## Versão 1.9.0

- Regressões com HTTP/XML local validam recusa do prefixo inicial, aceitação de ptz ou namespace padrão, preservação do namespace nos filhos, reutilização do formato aceito e ausência de repetição de ContinuousMove recusado. Cache de consultas continua sem duplicar cada formato por perfil.
- O teste de versão usa a constante real para não ficar preso à versão anterior. Analyze e suíte completa executados com versão 1.9.0/build 10 antes da geração do APK.
- O diagnóstico 1.8 real confirmou audioAnunciado=false e disponibilidade_audio=false em /onvif2. PTZ continuou indeterminado; a hipótese de compatibilidade XML da 1.9 ainda requer consulta na câmera real. Não foi validado controle físico.


## Versão 2.0.0 / build 11

- Flutter analyze sem problemas; suíte completa com 94 testes aprovados. A captura opcional da interface passou à parte. Ajustes finais de apresentação foram revistos com testes de interface e novas capturas.
- HTTP/XML local: descoberta manual não envia Stop/Move nem consulta capacidades; usa token real recebido no teste. Preflight confirma Stop em formato mínimo ou padrão; falha mantém movimento bloqueado. Movimento recusado não é repetido; velocidade solicitada 0,1, Timeout PT0.3S e ausência de URI de espaço inventado conferidos.
- Interface simulada: bloqueio enquanto Stop está pendente, cancelamento de ativação tardia ao ir para segundo plano, um pulso por pressão longa e desativação ao sair. Não é validação na câmera real.
- Captura: conexão inativa é recusada e imagem de uma sessão encerrada é descartada. No teste nativo Linux com libmpv e fonte RTSP sintética 640×360 + PCMA/16000, o mesmo screenshot(image/png) entregou PNG de 113984 bytes; vídeo e áudio decodificado avançaram. Não comprova compartilhamento no Android ou sincronia audível na Jortan.
- Resumo curto retém falhas recentes/primeira falha, limita eventos e remove senha configurada. Capturas de interface não usam a câmera nem credenciais reais. preview-control-test.png mostra estado simulado.
- Controle manual autorizado pelo usuário, mas movimento físico e obediência a Stop/Timeout ainda precisam ser testados na câmera. Assinatura Android SHA-256 92dc5dd6df4ad2f5cae7e284cd8fd5927dec4f5c3cbd010ca51d0666e4537bff mantida; versionCode 11, versionName 2.0.0 e minSdk 24 conferidos com apksigner/aapt antes da distribuição.


## Correção 2.0.1 / build 12

- Três regressões HTTP/XML novas conferem Action, To com porta/caminho reais, UUID v4 único por pedido, WS-Addressing 2004/08 no manual e 2005/08 no padrão, Content-Length e autenticação preservados, sem copiar IDs/senha ao relatório.
- O servidor sintético fecha a conexão quando falta roteamento e responde aos pedidos corrigidos. Isso é um teste da hipótese de compatibilidade, não prova da causa na câmera real.
- Se a conexão continua encerrando, os dois formatos ficam identificados no erro e a ativação continua bloqueada. O teste confirma que nenhum ContinuousMove pode ser enviado após preflight recusado.
- Analyze e suíte completa com 97 testes antes de distribuir. Sem alteração de interface, vídeo ou captura de imagem. Controle físico ainda pendente.


## Versão 2.1.0 / build 13

- Flutter analyze sem problemas; suíte completa com 100 testes aprovados. Captura opcional de interface aprovada separadamente e inspecionada; dados simulados, sem câmera ou senha real.
- Regressões HTTP: Stop encerra conexão sem resposta; alternativa ContinuousMove com velocidade zero aceita nos formatos padrão/mínimo e reutilizada. O preflight só envia paradas, sem movimento. Todas recusadas mantêm as setas bloqueadas. Movimento recusado nunca é repetido. Timeout curto PT0.3S e por pressão PT2S conferidos no XML. Nenhum espaço URI é inventado.
- Interface: renovação durante pressão, parada ao soltar, desativação em segundo plano e ausência de gesto longo capturado pelo tooltip. Controlador serializa movimentos, espera o último antes da parada e mantém limite de 5 s por pressão.
- O usuário confirmou movimento real no Onvier, com pausas durante pressão, e continuidade no Yoosee original. O registro local contém ContinuousMoveResponse e Stop sem resposta em /onvif/deviceio_service. Essa é evidência de referência; o Jortan 2.1 ainda precisa de validação de movimento, parada, timeout e fluidez na câmera real.
- Reprodução/captura de vídeo não alteradas. Nenhuma medida nova de latência ou sincronização de áudio; sem IPA. Site de download continua privado.

APK 2.1.0 conferido com aapt: versionCode 13, minSdk 24, ARM64. apksigner confirmou SHA-256 92dc5dd6df4ad2f5cae7e284cd8fd5927dec4f5c3cbd010ca51d0666e4537bff, igual à versão anterior.


## Versão 2.2.0 / build 14 — uso diário

- Flutter analyze sem problemas; suíte completa com 105 testes aprovados. Captura opcional passou separadamente; tela nova inspecionada no Flutter com dados simulados.
- Interface nova conecta sem movimento durante preparação, confirma parada antes de habilitar setas, salva perfil/serviço/formato, reutiliza ao reconectar e não chama consultas de capacidades recusadas. Recusa de parada não salva nem libera setas; reconexão recupera. Resposta tardia em segundo plano não libera movimento. Pressão renova, soltar pede parada; controladores anteriores continuam cobertos por regressões.
- HTTP/XML confirma preferência pela parada padrão com velocidade zero antes de Stop convencional, sem alterar a semântica de movimento. Formatos alternativos e bloqueio após falha continuam cobertos.
- Armazenamento protegido: migração sem preferência inicial, troca de fluxo sem perder preferência, preservação da configuração anterior e ausência de senha no registro de controle. URLs de outro host, com credenciais ou query, identidade diferente e schema desconhecido são recusados.
- O usuário confirmou movimento físico na 2.1, com pausas; os dois relatórios reais confirmam ContinuousMove e parada por velocidade zero. Esse resultado não significa detecção automática de movimento ou validação física do novo fluxo 2.2. As pausas não foram dadas como resolvidas.
- Sem mudanças no transporte/decodificação/captura de vídeo, áudio ou configuração WAN. iOS permanece fonte sem IPA. Guia de design incluído no código-fonte.

APK release final conferido: versionName 2.2.0, versionCode 14, minSdk 24; libapp.so AOT, depuração Android desabilitada, somente bibliotecas ARM64. apksigner confirmou o certificado SHA-256 92dc5dd6df4ad2f5cae7e284cd8fd5927dec4f5c3cbd010ca51d0666e4537bff, igual ao anterior. Cerca de 32,3 MB. Bibliotecas extras de plugins para outras ABIs foram excluídas, pois o motor entregue é ARM64.


## Versão 2.3.0 / build 15 — joystick e ações de vídeo

- Analyze sem problemas; suíte completa com 117 testes aprovados. Capturas opcionais do controle por setas e joystick passaram separadamente e foram inspecionadas; são dados simulados.
- Joystick: oito direções, centro neutro, soltura/cancelamento, desabilitação, botão Parar e remoção encerram movimento. Limite de 5 s impede reinício no mesmo gesto. Arraste não rola a página, inclusive com texto ampliado. Escolha Setas/Joystick persiste e é restaurada sem movimento.
- Controlador: resposta lenta usa apenas a última direção, sem posições intermediárias nem sobreposição; soltura cancela reinício após parada pendente; falha da parada não inicia direção pendente. Regressões de limites, encerramento e falha de movimento aprovadas. O agendamento é baseado na conclusão da resposta, sem polling periódico.
- Ações de vídeo testadas separadamente: entrada/saída de tela cheia com rótulos distintos e Redefinir zoom somente quando aplicado. A interface chama a API pública do reprodutor; tela cheia nativa em Android não foi executada neste ambiente. Confirmação física do novo joystick/agendamento também depende do aparelho.
- Evitados redesenhos com eventos de áudio repetidos e recompilação da expressão de filtro a cada log. Nenhum benchmark de CPU/FPS/latência foi realizado. Sem mudança de codec, probe HEVC, buffers, transporte, velocidade por eixo, timeout da câmera ou limite por pressão.
- APK release AOT ARM64 conferido: versionName 2.3.0, versionCode 15, depuração Android desabilitada e mesmo certificado SHA-256 92dc5dd6df4ad2f5cae7e284cd8fd5927dec4f5c3cbd010ca51d0666e4537bff. Preferências anteriores, assinatura e site privado preservados.


## Versão 2.4.0 / build 16 — acesso remoto com ponte Windows

- Flutter analyze sem problemas e 120 testes aprovados. Novas regressões: URL HTTPS sem credenciais/query/fragmento/caminho, recusa de formatos inseguros, persistência do endereço e chamada do visualizador sem senha local na URL. Uso local preservado.
- Android release AOT ARM64 conferido com aapt/apksigner: versionCode 16, versionName 2.4.0, atividade remota presente, depuração desabilitada e certificado anterior 92dc5dd6df4ad2f5cae7e284cd8fd5927dec4f5c3cbd010ca51d0666e4537bff. Visualizador remoto usa WebView do sistema com HTTPS, bloqueio de conteúdo misto, arquivo local e permissões de câmera/microfone; atividade não exportada. Compilação Kotlin aprovada. Não houve execução da atividade no Android real neste ambiente.
- Ponte em Go: 8 testes com detector de races aprovados; repetidos com Go 1.27.4. Login/cookies/CSRF, revogação de sessão, proteção HLS e configuração local, rate limit, validação de destino/XML, RTSP Digest e interleaved, normalização só com canais correspondentes, perfil real e parada zero, interrupção por heartbeat e parada pendente não descartada. Binário PE x64 Windows compilado; DPAPI, gerenciamento de processos e suspensão implementados, mas não executados em Windows aqui.
- Integração sintética em Linux/Chromium: RTSP H.264 + PCMA e RTSP HEVC sem áudio → ponte → HLS/H.264 640×360 reproduzido no navegador. Estado ready=4 e tempo de reprodução avançando, sem overflow em viewport 390×844 e sem erros de JavaScript. UI de joystick envia movimento/heartbeat/stop. Logout bloqueia HLS com 401. São testes sintéticos, não uso na câmera ou no Safari/iPhone reais.
- Túnel HTTPS é iniciado no notebook pelo cloudflared; o notebook precisa ficar ligado. URL gratuita muda ao reiniciar; nenhum encaminhamento de porta foi criado. O túnel no Windows/rede do usuário e o Safari do iPhone precisam da primeira execução no equipamento real. Fonte e guias acompanham os pacotes; site continua privado.


## Atualização visual 2.5.0

Análise Flutter sem problemas; suíte existente de 120 testes aprovada e novo teste de navegação Remoto/Ao vivo em 320×800 aprovado (121 testes no total). Capturas da interface sem câmera/credenciais em 390×844: início, remoto, configurações, imagem e som, setas e joystick. Preservados controles, gestos e transporte. O usuário confirmou o acesso remoto da Ponte 1.0.1; esta edição visual não foi executada em câmera/Android/iPhone físicos aqui. Ponte 1.1.0 verificada com H.264/PCMA e HEVC sintéticos no Chromium, tempo avançando em 640×360, logout protegendo mídia e gesto de joystick encerrado com parada.
