# Jortan Viewer 2.1.0

App Flutter para assistir a uma câmera RTSP Jortan/Yoosee diretamente no celular, na mesma rede Wi-Fi. O PC pode ficar desligado. App independente, sem vínculo com Jortan ou Yoosee.

## Usar no Android

1. Transfira o APK de teste para o celular e abra o arquivo. Se o Android pedir, permita a instalação por esse navegador ou gerenciador de arquivos.
2. Conecte o celular ao Wi-Fi da câmera e abra **Jortan Viewer**.
3. Toque em **Configurar minha câmera**. Confira IP `192.168.1.100`, porta `554`, usuário `admin` e caminho `/onvif1`.
4. Digite a **senha local RTSP/ONVIF** da câmera, que pode ser diferente da senha de sua conta Yoosee.
5. Deixe o transporte em **Automático** e toque em **Salvar e testar conexão**.
6. Se não vier vídeo, abra **Diagnóstico**. Experimente `/onvif2` ou o caminho documentado pelo fabricante e teste novamente.

A indicação **Ao vivo** só aparece após o primeiro quadro renderizado. A primeira tentativa usa TCP; se falhar, ela é encerrada e o app tenta UDP. Um TCP conectado sem vídeo não comprova bloqueio de firewall.

A senha é salva no armazenamento protegido do aparelho, com backup Android desabilitado. Os relatórios removem credenciais antes de guardá-las em memória; parâmetros de consulta do caminho não são exportados. Os relatórios ainda contêm IP e dados técnicos da conexão.

Ao sair do app, a conexão é encerrada. Ao voltar, toque em conectar. Depois de uma perda de vídeo são permitidas até três reconexões (2, 5 e 10 segundos). Falhas iniciais são exibidas após as tentativas dos transportes selecionados.

## Requisitos e limites

- Android 7.0/API 24 ou superior; APK ARM64 para celulares Android de 64 bits.
- Uma câmera por vez, com RTSP habilitado. Celular e câmera devem conseguir se comunicar na rede local.
- Vídeo e escuta do áudio RTSP; giro/inclinação/zoom contínuos quando anunciados por ONVIF. Sem microfone, gravação ou acesso à nuvem Yoosee.
- Sem acesso fora de casa nesta versão. Uma rede de convidados com isolamento pode impedir a conexão.
- O vídeo RTSP local não é criptografado pelo aplicativo. Use sua rede privada.
- O APK é uma versão de teste assinada com chave de desenvolvimento; não é uma publicação na Play Store.

## Desenvolvimento

Ferramentas usadas: Flutter 3.47.9, Dart 3.13.7, JDK 21, Android SDK 36 e NDK 28.2.13676358. Dependências resolvidas em `pubspec.lock`.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

Saída: `build/app/outputs/flutter-apk/app-debug.apk`.

Para distribuição de produção, configure uma chave de assinatura própria no Android. A configuração release de desenvolvimento segue o padrão do Flutter e usa a chave debug; não publique assim em uma loja.

## iPhone

O código compartilhado, projeto Xcode, configuração CocoaPods, descrição de Rede Local e entitlement do Keychain estão preparados. **A versão iOS não foi compilada nem testada neste ambiente Linux. Não há IPA entregue.**

Em um Mac com Xcode e CocoaPods:

```sh
flutter config --no-enable-swift-package-manager
flutter pub get
cd ios
pod install
cd ..
flutter build ios --no-codesign
```

Abra `ios/Runner.xcworkspace`, selecione sua equipe de assinatura e o iPhone no Xcode. A instalação no aparelho exige provisionamento Apple. Uma conta gratuita permite testes pessoais sujeitos às limitações da Apple; TestFlight/App Store exige Apple Developer. Permita **Rede Local** quando solicitado. O projeto usa iOS 15 ou superior.

## Verificação

Consulte `docs/VALIDACAO.md` para distinguir testes automatizados, fonte RTSP controlada e validação pendente em aparelho/câmera real. A pasta `integration_test` permite testar o reprodutor nativo em um dispositivo com a fonte sintética, sem usar senhas reais.


## Atualização 1.1.0

Instale o novo APK por cima da versão anterior: o identificador do app e a assinatura foram mantidos, assim como o formato da configuração protegida. Não é necessário desinstalar.

O diagnóstico usa schema 2: teste direto TCP/RTSP (OPTIONS e DESCRIBE), desafio Basic/Digest, códigos e CSeq enviados/recebidos, SDP/codecs, versões/opções do motor, eventos com horário e exceções. Esse teste de controle não confirma entrega de RTP/UDP. Falhas do teste direto não impedem tentar a reprodução nativa.

“Property not found” não significa caminho RTSP inexistente. O app só classifica um caminho como rejeitado quando há evidência RTSP 404; avisos recuperáveis do motor não encerram a reprodução. CSeq divergente é tratado como indício, sem afirmar uma causa comprovada. O 401 inicial de um desafio seguido de 200 não é tratado como senha recusada.

O trace detalhado é usado na abertura; durante o vídeo o motor reduz o registro a avisos/erros. Por tentativa são preservadas até 320 linhas (80 iniciais e 240 recentes), mais até 100 erros/avisos relevantes; descartes são informados. “Compartilhar arquivo” exporta o JSON inteiro sem depender do limite de texto do compartilhamento Android. Relatórios grandes devem ser compartilhados como arquivo.

Senhas, URLs com credenciais, Authorization e parâmetros Digest sensíveis são removidos antes de reter os logs. Erros de armazenamento omitem o conteúdo da configuração. O relatório ainda contém IPs locais e informações técnicas do dispositivo.


## Atualização 1.2.0 — compatibilidade TCP

O relatório real mostrou SETUP solicitado como `RTP/AVP/TCP;interleaved=0-1` e resposta `RTP/AVP;interleaved=0-1`, rejeitada pelo FFmpeg com `Nonmatching transport in server reply`. A senha e o caminho já haviam sido aceitos.

A tentativa TCP usa uma ponte restrita a 127.0.0.1, dentro do celular. Ela só completa `/TCP` quando o cabeçalho recebido omite esse marcador, os canais intercalados correspondem ao pedido e não há transporte UDP explícito, portas UDP ou multicast. Os bytes RTP/RTCP não são alterados. Autenticação Digest é recalculada para a URI original da câmera; URLs de controle são encaminhadas pela ponte. Conexões são fechadas e a sessão recebe TEARDOWN no encerramento quando necessário.

O relatório inclui cabeçalho original/corrigido, respostas e contadores de RTP. Dumps caractere por caractere são descartados antes do armazenamento. A seleção automática evita repetir o teste de controle TCP ao passar para UDP e aguarda um intervalo entre transportes. O campo de endereço anteriormente chamado local foi corrigido para endereço alvo (a API Socket.address não identifica a interface de saída).

Teste reproduzível: `scripts/broken_rtsp_fixture.py` retira `/TCP` da resposta de uma fonte MediaMTX. Sem a compatibilidade o FFmpeg falha; `tool/rtsp_bridge_probe.dart` confirma decodificação com uma correção. Uma fonte normal reproduz sem correção. A validação da câmera real no Android ainda depende de testar este APK no aparelho.


## Atualização 1.3.0 — Buscar câmera

Em Câmera → Buscar câmera no Wi-Fi, confira a faixa sugerida e toque em Buscar agora. Selecione um resultado para preencher IP e porta; os campos de usuário, senha e caminho permanecem no formulário. A busca não testa senhas e não salva nem conecta automaticamente.

A busca verifica respostas RTSP OPTIONS nas portas configurada, 554 e 8554, e envia WS-Discovery ONVIF por unicast. Uma porta aberta sem uma resposta RTSP válida não é marcada como serviço RTSP. ONVIF e RTSP são identificados separadamente; a porta 554 é apenas sugerida quando o dispositivo responde somente por ONVIF. Nem toda câmera aceita descoberta unicast.

O serviço limita a faixa a /24 até /32 em redes IPv4 privadas/link-local, com até 24 conexões em paralelo, prazo curto por porta e cancelamento. O Wi-Fi é inferido das interfaces do aparelho, com edição manual da faixa. A interface informa ausência de resultados, permissões e limitações. A reprodução é encerrada antes da busca para reduzir concorrência na câmera.

Os resultados da busca entram no relatório de diagnóstico. No iOS, a descrição de acesso à Rede Local cobre busca e reprodução; não foi adicionado entitlement de multicast, pois esta descoberta usa unicast. A versão nativa iOS continua sem compilação/assinatura neste ambiente Linux.

Conforme a escolha do usuário, o próximo teste no iPhone será com VLC já disponível na App Store, no mesmo Wi-Fi. A documentação em docs/IPHONE-VLC.md inclui endereço e orientações com senha fictícia. A compatibilidade do VLC com o firmware desta câmera ainda não foi validada. A alternativa de ponte web em PC ficou em espera, sem publicação.


## Atualização 1.4.0 — movimento, zoom e áudio

Na aba **Ao vivo**, toque em **Ouvir câmera** para liberar o volume ou em **Silenciar câmera** para desligá-lo. O áudio começa silenciado em cada conexão. A presença de áudio depende do fluxo da câmera; consulte `parametros_audio` no diagnóstico. Esta função é de escuta e não envia voz pelo microfone. O fluxo agora negocia vídeo e áudio, inclusive pela ponte TCP.

Use dois dedos sobre o vídeo para ampliar a imagem no celular (zoom digital até 4×). O botão de redefinir zoom restaura a imagem. Isso não altera o zoom físico da câmera.

Toque em **Verificar controles ONVIF**. O app consulta GetCapabilities, GetProfiles e GetConfigurationOptions; só habilita giro/inclinação e zoom contínuos anunciados no perfil selecionado. Use Buscar câmera para preencher o endpoint ONVIF ou informe a URL ONVIF opcional na aba Câmera (mesmo IP, sem senha). Sem endpoint conhecido, são testadas as portas HTTP 80, 8899, 8999, 8080 e 5000 no caminho /onvif/device_service; essa lista não cobre todos os fabricantes.

Segure as setas para mover; solte para enviar Stop. Cada pulso solicita Timeout de 0,6 segundo e a pressão contínua é limitada a 5 segundos. Cancelar gesto, desconectar, trocar de aba e sair do app também interrompem os pulsos e tentam Stop. Isso depende de o firmware respeitar esses comandos; falhas ficam no diagnóstico. Não são enviados comandos proprietários Yoosee. Firmware sem PTZ contínuo/zoom anunciado pode exigir uma implementação diferente.

ONVIF usa UsernameToken PasswordDigest com nonce aleatório e HTTP Basic/Digest quando solicitado. O relógio UTC da câmera é consultado quando disponível para ajustar a autenticação. Endpoints anunciados fora do IP configurado e redirecionamentos são recusados; certificado HTTPS é validado normalmente. Diagnósticos não incluem SOAP bruto, senha ou cabeçalhos de autenticação.

Instale por cima da versão anterior para preservar os dados. Esta atualização entrega APK Android; o código compartilhado para iOS não equivale a um instalador para iPhone.


## Atualização 1.5.0 — compatibilidade ONVIF e diretrizes de interface

- O relatório real de 05/11/2026 confirmou GetCapabilities e GetProfiles na porta 5000. As falhas de GetConfigurationOptions eram achatadas em falha_de_rede, sem porta nem etapa; isso não comprovava ausência de PTZ.
- O cliente agora envia SOAP com Content-Length UTF-8 explícito, SOAPAction e Connection: close. A consulta usa conexão nova para evitar incompatibilidades de servidores embarcados com keep-alive/chunked POST. Apenas consultas de leitura podem repetir após conexão encerrada/reset; ContinuousMove nunca é repetido automaticamente.
- GetConfigurationOptions tem alternativas por GetNode/GetNodes, correlacionando o nó ao perfil. Endpoints permanecem no IP configurado; se a porta PTZ anunciada divergir, consultas de leitura comparam o mesmo caminho na porta ONVIF confirmada e o endpoint de dispositivo. TLS inválido não é ignorado e não se faz movimento durante a inspeção. Não são inventadas capacidades nem copiados limites de outro nó.
- O diagnóstico diferencia consulta indeterminada, ausência de configuração nos perfis e ausência de movimento contínuo anunciado. Registra porta, caminho, etapa HTTP, tipo da exceção/código do sistema quando disponível, subcódigos SOAP conhecidos e origem das capacidades. Não inclui SOAP bruto, cabeçalhos de autenticação nem texto arbitrário da câmera.
- A negociação RTSP mantém o último status fora do buffer de logs, evitando transformar o 401 inicial normal em erro de senha depois de receber 200. O caso de HEVC sem dimensões/VPS/PPS/SPS tem diagnóstico específico. A análise inicial de áudio/vídeo foi ampliada para 10 segundos e a preparação total para 24 segundos; o fallback UDP foi preservado. Avisos repetidos não ocupam toda a lista importante; trace ao vivo é filtrado no app.
- O tema do app e o site seguem as regras persistidas em docs/DESIGN.md: contraste 4,5:1, espaços 8/16/24/32, dois pesos 400/600, botão mínimo 48, alvos mínimos 44, uma ação principal e badges sem borda. AGENTS.md referencia esse guia para as próximas atualizações.

**Ainda precisa de teste na Jortan real:** a correção melhora a consulta e a compatibilidade, mas não comprova que este firmware aceite os comandos de movimento. Se a verificação falhar, envie novamente o JSON completo. O vídeo foi confirmado pelo usuário em UDP e o relatório mostrou áudio decodificado em 16 kHz; escuta real e controle físico não são comprovados por testes em laboratório.


## Atualização 1.6.0 — descoberta dos serviços ONVIF

O relatório real da versão 1.5 confirmou vídeo TCP, GetCapabilities e GetProfiles na porta 5000. Os endereços anunciados foram incomuns: Media em /onvif/ptz_service e PTZ em /onvif/deviceio_service. O app 1.5 não consultava PTZ no caminho /onvif/ptz_service; suas consultas por deviceio_service e device_service foram encerradas antes de receber cabeçalhos. Isso não demonstra que a câmera não tenha controle físico.

- Consulta GetServices e associa Media/PTZ pelo namespace exato; compara com os endereços anunciados em GetCapabilities. XAddr é lido como filho direto ou atributo, sem aproveitar um XAddr de uma extensão aninhada.
- Se preciso, consulta PTZ no caminho convencional /onvif/ptz_service, no endpoint de mídia confirmado e no endpoint de dispositivo, sempre no mesmo IP. Nenhum nome de caminho por si só habilita movimento: exige resposta PTZ válida e capacidades anunciadas para o perfil/nó.
- Reutiliza resultados/falhas de consultas idênticas dentro da mesma inspeção para reduzir repetição. Não movimenta durante a verificação e não repete ContinuousMove automaticamente.
- Prazo por consulta ampliado para 4 segundos, pois o relatório mostrou GetCapabilities levando cerca de 1,7 segundo no limite anterior de 1,8. Orçamento entre consultas de capacidades PTZ: 32 segundos; descoberta inicial e uma consulta já iniciada podem ampliar o tempo total.
- O erro final preserva uma falha relevante (como timeout na porta 5000) em vez de sempre mostrar a primeira porta recusada. Diagnóstico inclui os endpoints candidatos, fontes dos serviços e prazos de consulta, sem credenciais.
- Vídeo, áudio e regras de design da versão anterior foram preservados. O controle físico ainda precisa de teste na Jortan real.

Para comparar alternativas para iPhone/Safari, veja docs/WEB-PONTES.md. Ainda não foi escolhida/instalada uma ponte web no local; um servidor de vídeo não resolve automaticamente os comandos PTZ.


## Atualização 1.7.0 — imagem, atraso e diagnóstico PTZ

A tela ao vivo agora oferece Mais detalhes (/onvif1) e Mais fluido (teste de /onvif2 com ajustes para menor atraso), informa a resolução recebida e permite Atualizar transmissão por reconexão. Não se promete HD no fluxo alternativo nem atraso zero. O modo Menor atraso também está nas configurações para manter um caminho personalizado. Preferências são salvas sem alterar usuário/senha/transporte/URL ONVIF; configuração antiga migra com ajuste de compatibilidade. Veja docs/IMAGEM-E-ATRASO.md.

O áudio inicialmente fica com aid=no; o volume zero anterior ainda deixava a faixa ativa como referência de sincronização. Ouvir câmera seleciona aid=auto e volume 100; Silenciar zera o volume e desativa a faixa. Nenhum microfone foi adicionado.

No relatório 1.6, GetServices retornou HTTP 200, mas nenhum serviço Media/PTZ foi reconhecido. A versão 1.7 aceita entradas com contêineres alternativos ou atributos Namespace/XAddr, normaliza apenas a barra final de namespaces conhecidos e registra um resumo limitado da estrutura do corpo e dos serviços. Não exporta SOAP bruto, headers, nonces ou senha. As chamadas PTZ usam o prefixo convencional tptz com o mesmo namespace; Device/Media mantêm o formato já aceito.

Se GetConfigurationOptions/GetNode/GetNodes falharem, o app só oferece **Ativar teste de movimento** quando o próprio PTZConfiguration do perfil declarar explicitamente um espaço genérico contínuo ONVIF reconhecido. Um URI vendor ou campo ausente não habilita teste. Esse estado fica separado das capacidades consultadas: não comprova comando aceito nem movimento físico.

O teste requer ativação manual com vídeo conectado, usa velocidade normalizada reduzida (0,1), apenas um pulso por pressão, parada da pressão após 300 ms e Timeout solicitado de 600 ms. Stop segue o comando em andamento; o botão Parar força Stop mesmo quando o controlador não tem movimento pendente. Não se envia movimento durante a inspeção nem se repete um comando automaticamente. Os limites genéricos normalizados vêm da especificação ONVIF PTZ seção 5.7.3, condicionados à declaração explícita do perfil; não são limites consultados nesta câmera. O firmware precisa respeitar Stop/Timeout, e o controle real segue pendente.

Referência: https://www.onvif.org/specs/srv/ptz/ONVIF-PTZ-Service-Spec.pdf


## Atualização 1.8.0 — motivo da recusa ONVIF e áudio por fluxo

O relatório real da versão 1.7 mostrou GetConfigurationOptions devolvendo HTTP 200 com uma falha SOAP, sem subcódigos reconhecidos. Agora a leitura aceita faultcode/faultstring de SOAP 1.1 e Code/Value/Reason/Text de SOAP 1.2, mesmo quando o HTTP é 200. O diagnóstico preserva código e motivo limitados, com credenciais configuradas removidas, e nomes dos elementos da falha. Não exporta SOAP bruto, conteúdo de detail ou cabeçalhos de autenticação. Códigos desconhecidos permanecem SOAPFault na classificação, com o valor recebido separado para investigação.

Isso melhora o diagnóstico; não comprova correção do comando nem movimento físico. Os dois perfis reais não declararam espaços genéricos contínuos e as consultas de capacidades falharam, portanto o app continua sem inventar limites para habilitar motores.

A troca de qualidade foi confirmada pelo usuário: /onvif1 entrega 1920×1080 e /onvif2 entrega 640×360. No teste de /onvif2 a câmera anunciou apenas vídeo. O app agora sinaliza ausência de áudio anunciado neste fluxo e orienta Mais detalhes para testar som. A disponibilidade acompanha o SDP e as faixas identificadas pelo motor, volta a desconhecida a cada sessão e não confunde faixa anunciada com som audível ou sincronizado. Sincronização de áudio e atraso ponta a ponta continuam sem medição real.


## Atualização 1.9.0 — compatibilidade de serialização PTZ

O novo relatório real preservou a resposta SOAP Sender: Method tptz:GetConfigurationOptions not implemented: method name or namespace not recognized. Isso é uma recusa de despacho do método, não uma comprovação de senha errada, ausência de motores ou incompatibilidade de todo o PTZ. O usuário confirmou movimento pelo aplicativo original; esse teste não identifica qual protocolo o aplicativo original usa.

Consultas PTZ de leitura agora podem testar no máximo três serializações XML equivalentes do mesmo namespace oficial ver20/ptz/wsdl: prefixos tptz, ptz e namespace padrão sem prefixo. A alternativa só é acionada após recusa explícita de método ou encerramento/reset da conexão. Não altera namespace, host, credenciais, endpoint nem inventa capacidades. Uma resposta válida memoriza o formato por endpoint para as próximas chamadas. Device e Media preservam a serialização anterior. Erros de autenticação não acionam alternativas. ContinuousMove e Stop nunca são repetidos automaticamente.

A documentação comunitária https://github.com/victorbillyph/Yoosee-camera-documentation mostra exemplos Yoosee com prefixo ptz; isso motiva uma hipótese de compatibilidade, não comprova comportamento desta câmera. Pela norma XML os prefixos são equivalentes. A mudança só libera controles se a câmera efetivamente devolver capacidades válidas pelas consultas existentes. Não foi executado movimento físico neste ambiente.

O diagnóstico passou a colocar controlesCamera antes dos logs extensos de reprodução para facilitar envio por texto. Recomenda-se compartilhar o arquivo inteiro.


## Versão 2.0.0 — teste manual, imagem e diagnóstico curto

- Modo experimental Yoosee solicitado pelo usuário. Obtém tokens reais, oferece ativação manual e exige resposta prévia a Stop. Usa um único pulso curto por direção, sem zoom físico e sem repetir movimentos automaticamente. A inspeção continua sem movimentos. Veja docs/CONTROLE-MANUAL.md para formato, limites, fontes e cancelamentos. Não equivale a controle físico validado.
- Tela ao vivo com vídeo em 16:9, controle mais próximo do vídeo e compartilhamento de um quadro PNG pelo menu de compartilhamento do sistema. A captura entrega o quadro do reprodutor; não inclui o zoom digital feito na tela e não grava vídeo. Não envia imagem automaticamente a nenhum serviço.
- Diagnóstico com resumo de vídeo/áudio/controle e **Copiar resumo curto**, sem os registros extensos do reprodutor. O relatório completo e o arquivo JSON continuam disponíveis, com credenciais removidas.
- Testes de ativação, parada prévia, erros, cancelamento no ciclo do app, pulso único, captura interrompida e resumo sem credenciais. Vídeo/áudio RTSP e assinatura Android preservados. PNG e áudio decodificado também conferidos com fonte sintética e libmpv no Linux; ainda requerem validação no Android real.

Não há ponte web de vídeo instalada nem IPA assinado nesta entrega. O site privado distribui o Android e o código-fonte atualizado; VLC no iPhone já foi confirmado pelo usuário.


## Correção 2.0.1 — roteamento das mensagens PTZ

O relatório real da 2.0 mostrou Stop sem resposta HTTP nos dois formatos tentados. Ao conferir o código executável da referência comunitária, foi identificada uma diferença concreta: ele inclui Action, To e MessageID no cabeçalho WS-Addressing, campos ausentes nos pedidos PTZ do app até a 2.0. Essa omissão foi corrigida; a necessidade desses campos nesta unidade ainda não foi comprovada por teste real.

O modo mínimo Yoosee usa WS-Addressing 2004/08 como a referência; o formato padrão PTZ usa 2005/08. Action corresponde à operação, To ao endpoint real validado (com a porta efetiva) e MessageID é um UUID novo por pedido. Device e Media preservam o corpo já aceito. Não se enviam cabeçalhos brutos, IDs ou credenciais aos relatórios; os erros incluem apenas versão de endereçamento, ação e destino técnico. O resumo curto agora inclui respostas validadas de Stop/ContinuousMove, sem tratar resposta como movimento físico.

Teste HTTP local reproduz encerramento sem cabeçalho quando falta WS-Addressing e aceita os pedidos corrigidos; isso valida o formato e a regressão, não demonstra a causa do comportamento da câmera real. Preflight Stop, pulso de 300 ms e ausência de repetição automática de movimento foram preservados.

Fontes: https://github.com/victorbillyph/Yoosee-camera-documentation/blob/main/camera_control.py ; https://www.w3.org/2002/ws/addr/ ; https://www.onvif.org/profiles/specifications/ .

## Versão 2.1.0 — controle por pressão e parada alternativa

O teste manual prioriza o serviço PTZ anunciado. Ao ativar, exige resposta válida a Stop ou à parada equivalente ContinuousMove com velocidade zero. Toque curto continua sendo o primeiro teste. A opção **Segurar para mover** renova movimentos enquanto pressionado, com timeout solicitado de 2 s e limite de 5 s por pressão; soltar pede a parada confirmada, sem enfileirar movimentos. Credenciais, assinatura e reprodução permanecem preservadas. Movimento/fluidez no Jortan precisam de teste real; o usuário confirmou funcionamento no Onvier, com pausas, e continuidade no Yoosee original. Veja docs/CONTROLE-MANUAL.md.
