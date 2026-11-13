# Validação da ponte 1.5.0

16 testes Go com detector de races aprovados, inclusive usando Go 1.27.4. Reprodução integrada sintética via Chromium em viewport 390×844: H.264/PCMA e HEVC sem áudio convertidos para HLS H.264 640×360, readyState 4, reprodução avançando, sem erros JS e sem overflow. Sair da conta revoga acesso HLS (HTTP 401). UI remota de joystick testada com respostas simuladas: 3 pedidos, incluindo parada. Controles de câmera exercitados em HTTP/XML sintético e com interrupção por perda de heartbeat; não houve movimento físico nesta validação.

Código compilado para PE Windows x64. Não foi executado em Windows ou iPhone reais, nem foi possível acessar a rede doméstica da câmera a partir deste ambiente. DPAPI, job object e solicitação de manter o Windows ativo são implementações que precisam da execução no notebook. O túnel real é iniciado quando o usuário abre a ponte; nenhum vídeo doméstico foi publicado aqui. URL gratuita pode mudar ao reiniciar. Não há medida de atraso ponta a ponta ou sincronização audível.

Regressões da 1.0.1: consulta anônima de sessão sem CSRF e mídia ainda protegida; favicon e metadado mobile; CRLF antes de resposta RTSP com RTP preservado; grafia CSeq; URI com porta 554 implícita sem alterar outro host; estado responsivo durante lançamento de processo bloqueado; classificação sem texto bruto de credenciais. Teste de navegador com /api/play sem resposta terminou a espera, reabilitou Conectar e disponibilizou diagnóstico. HEVC e H.264 reproduziram em 640×360 com tempo avançando; joystick e logout continuaram funcionando. A causa específica no notebook do usuário ainda depende do diagnóstico real.

Interface 1.1.0: layouts de login e visualizador verificados em 320, 390, 844 e 1440 px, sem overflow horizontal nem erros JS. Mostrar/ocultar senha e diagnóstico recolhido funcionaram. Reprodução H.264/PCMA e HEVC sem áudio repetida com fonte sintética; joystick e parada com respostas simuladas preservados. Sem nova validação física do controle ou execução do binário Windows neste ambiente.


## Retomada após inatividade — 1.1.1

Caso de reprodução sintética por 95 segundos sem interação passou, sem reconectar o conversor e com renovações de visualização autenticadas. Em teste separado, pausa manual preservada ao trocar de visibilidade; conversor encerrado e pasta HLS removida para reproduzir expiração em segundo plano; retorno à página criou nova transmissão e reproduziu sem navegar/recarregar. Uma playlist HTTP 404 injetada foi recuperada automaticamente. Rede indisponível foi simulada para confirmar limite de três tentativas; o botão Reconectar funcionou depois do limite. Sair durante a recuperação cancelou a próxima tentativa e a mídia voltou a exigir autenticação. Sem erros JS nesses testes.

Teste Go com tempo avançado verifica que renovação impede expiração, ausência por mais de 90 segundos limpa a playlist e renovação isolada não inicia vídeo. Anônimo, falta de CSRF e método GET não renovam. Movimento não é retomado automaticamente. Safari/iPhone e a ocorrência específica na rede real não foram reproduzidos neste ambiente.


## Endereço fixo Tailscale — 1.2.0

16 testes Go com detector de races aprovados: nome DNS .ts.net e link de autorização validados; comandos em primeiro plano sem --bg/reset; saída de status limitada; login obrigatório e token de autorização acessível só ao painel local; listener público separado bloqueia /setup e APIs locais mesmo com Host e nonce forjados; origem, CSRF e cookies Secure preservados; cancelamento encerra CLI simulada e listener.

Reprodução H.264/PCMA e HEVC sem áudio sintéticas no Chromium por proxy do Funnel simulado: 640×360, tempo avançando, login público e mídia protegidos, painel bloqueado (404/403), logout revoga HLS (401), sem erros JS. O teste simula CLI e encaminhamento HTTPS no navegador, sem registrar domínio, conta ou dispositivo reais no Tailscale. Não comprova throughput ou acesso público real pelo Funnel, execução em Windows ou Safari/iPhone. O usuário precisa instalar o cliente oficial no notebook, entrar na conta Personal e autorizar o recurso.

Fontes de integração: https://tailscale.com/docs/features/tailscale-funnel ; https://tailscale.com/docs/reference/tailscale-cli/funnel ; código oficial cmd/tailscale/cli/serve_v2.go e ipn/ipnlocal/serve.go (sessão em primeiro plano e preservação do Host). Documentação de preços e limites consultada em 12/11/2026. Não há compra de domínio ou assinatura neste pacote.


## Tela cheia, controles e notificações — 1.3.0

20 testes Go com detector de races aprovados. Novos testes verificam aquecimento, movimento sintético, variação uniforme de luz, intervalo de 1 minuto e supressão após PTZ; quadros crus divididos em blocos; monitoramento desativado por padrão; autenticação/CSRF; preservação do conversor com análise ativa; expiração sem análise; persistência e redefinição de assinaturas após troca de configuração.

Web Push exercitado contra receptor simulado: descriptografia independente RFC 8291 (ECDH/HKDF/AES-GCM), assinatura ES256 VAPID, audiência, TTL, invalidação 410 e validação de endpoints. Service worker testado em VM: notificação visível, clique limitado à própria origem e nenhum cache de mídia. Nenhuma notificação real foi enviada para Apple/Google/Mozilla nesta validação.

Chromium com vídeo sintético em 390×844, 320×700 e 844×390: controle a 8 px da imagem, sem overflow; tela cheia por CSS com API nativa indisponível, rotação/inversão/saída e coordenadas do joystick com parada. Análise no FFmpeg real disparou evento de imagem sintética e foi desativada após o teste. Entrega Web Push com app fechado e orientação no Safari de iPhone real ainda não foram verificadas; usar Enviar teste no aparelho.

## Central da casa — 1.4.0

24 testes Go com detector de races aprovados. Novos casos verificam migração da configuração 1.3 sem perder preferências, perfis independentes, modo Dormir, análise sem notificação, histórico limitado a 300 eventos/sete dias, persistência, redefinição ao trocar configuração, validação de horários, rotinas diárias no fuso do notebook, ausência de repetição após reinício no mesmo minuto, recusa de horários conflitantes e proteção HTTP/CSRF de todas as novas APIs.

Leituras de energia simuladas: tomada, saída da tomada, 20%, 8%, recuperação e leitura desconhecida. Verificadas transições sem duplicação, perda de imagem com monitoramento ativo e recuperação. Nenhuma leitura física de bateria Windows foi feita no Linux.

Chromium com RTSP H.264/PCMA e FFmpeg reais usando câmera sintética: reprodução, evento de movimento no histórico, troca de modo, edição de perfil sem notificações, adicionar/desativar/remover rotina, filtros e exclusão de histórico. Layout 320×700, 390×844 e 844×390 sem overflow; tela cheia por rotação preservada. Interrupção da API da ponte removeu a confirmação de disponibilidade. Estado de bateria baixa renderizado com resposta simulada. Logout limpou histórico da página e revogou acesso HTTP (401), sem erros JS.

Service worker em VM: avisos de bateria, energia, perda/retomada de imagem, notificação de teste, clique limitado à própria origem e nenhum cache HLS. Push criptografado continua coberto pelo teste RFC 8291/VAPID. Nenhum aviso foi enviado a um aparelho real neste ambiente. Executável compilado para Windows x64; DPAPI e GetSystemPowerStatus precisam de execução no notebook real.

## Identidade Ninho Monitor — 1.5.0

24 testes Go com detector de races aprovados após adicionar os ativos da marca. No Chromium, vídeo sintético, histórico, modos, perfis, rotinas, filtros, limpeza de histórico, desconexão, logout e rotação de tela cheia passaram sem erros JavaScript. Layouts 320×700, 390×844 e 844×390 sem overflow. Capturas do login verificaram a nova marca e a fonte local. Não houve validação física nova da câmera ou iPhone.

O site de download preserva o mecanismo de reconstrução e SHA-256, o APK Android existente e a audiência privada. Links, contraste e conteúdo foram verificados. A prévia de navegador gerenciada do Sites não estava disponível; a página hospedada não foi validada visualmente por esse ambiente.
