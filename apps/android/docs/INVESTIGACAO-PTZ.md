# Estado da investigação do controle físico

Atualizado com o diagnóstico real 2.0.1/build 12 enviado pelo usuário em 06/11/2026 às 11:01 UTC.

## Nova evidência: controle funcionando no Onvier

O usuário relatou que os controles funcionaram no Onvier 22.45 Free e enviou telas da câmera local. Identificação exibida: fabricante Technology, modelo IPC, firmware 40.00.40. O relato fornece uma referência independente de controle ONVIF funcional nesta unidade; não tratar mais a ausência de PTZ ONVIF como conclusão provável sem confrontar essa evidência.

O texto recebido mistura a câmera local com outro dispositivo de demonstração em um endereço externo. As respostas com fabricante MERIT-LILIN e modelo Z7R8082EX25 pertencem a esse outro endereço e **não identificam a câmera do usuário**. Os horários/autenticação desse dispositivo também não devem ser usados para calcular desvio do relógio da câmera local. Não acessar os endereços externos do log para investigar esta câmera.

As telas mostram perfis MainStream 1920×1080 e SubStream 640×360, fabricante/modelo/firmware locais e HEVC + G.711 A-Law durante a reprodução principal. O perfil rotulado H.264 não supera a evidência do fluxo efetivamente identificado como H.265.

O log colado termina durante GetServices e não inclui o pedido/resposta de movimento bem-sucedido. Foi solicitado um trecho posterior a tocar/soltar a seta, com ContinuousMove, RelativeMove ou Stop e destino local. A próxima comparação deve identificar operação, endereço PTZ, token de perfil, autenticação e semântica de parada antes de atribuir uma causa ao nosso erro. Cabeçalhos de autenticação e credenciais devem ser removidos do material compartilhado.

O texto de acesso WAN é uma sugestão genérica do Onvier; não constitui autorização para abrir portas ou alterar o roteador. O teste atual permanece no Wi-Fi local.

- RTSP TCP continua recebendo HEVC 640×360 em /onvif2. Este fluxo não anuncia áudio.
- O usuário confirmou que o aplicativo original move fisicamente a câmera. O protocolo usado pelo aplicativo original ainda não foi identificado.
- GetCapabilities e GetProfiles responderam anteriormente na porta 5000. Dois perfis possuem PTZConfiguration, mas sem os espaços contínuos consultados/declarados exigidos pela descoberta automática.
- GetConfigurationOptions devolveu SOAP Sender indicando método/namespace não reconhecido; GetNode/GetNodes encerraram a conexão nas alternativas testadas.
- O preflight Stop do modo manual também falhou. Na 2.0.1 os erros já identificam WS-Addressing 2004/08 (mínimo Yoosee) e 2005/08 (padrão). O usuário testou alternativas de serviço e ainda recebeu encerramento antes do cabeçalho HTTP.
- Portanto, a adição de Action/To/MessageID não resolveu o problema observado. Não apresentá-la como causa comprovada nem propor repetir apenas essa correção.
- O resumo recebido não contém resposta Stop validada nem movimento manual solicitado. O teste permanece desativado. Não inferir que a câmera não possui motores, que todo ONVIF está indisponível ou que a senha está errada.

## Evidência necessária para o próximo passo

1. Identificação do modelo/firmware e nome exato do aplicativo original. Solicitação feita ao usuário; não pedir senha, serial ou QR code.
2. Comparação com outro cliente ONVIF no mesmo Android/Wi-Fi. Onvier oferece configuração de dispositivo ONVIF e controle PTZ físico. Usar 192.168.1.100, porta 5000 e, se solicitado, /onvif/device_service. Observar giro físico; reprodução de vídeo ou zoom digital não validam PTZ.
3. Um cliente independente funcionando fornece uma referência útil; uma segunda falha não comprova por si só ausência de suporte. Qualquer log desse cliente precisa passar por remoção de credenciais antes de ser compartilhado.

Referências oficiais do cliente independente:

- https://www.ipcent.com/mobile/onvifer
- https://www.ipcent.com/mobile/Help/onvifer
- https://play.google.com/store/apps/details?id=net.biyee.onvifer

Não distribuir uma nova versão apenas com outra hipótese de formato sem evidência adicional. Preservar vídeo, assinatura e o bloqueio do teste enquanto Stop não é confirmado, conforme as regras solicitadas para o modo manual.

## Nova evidência local e implementação 2.1

O segundo registro inclui ContinuousMoveResponse válido do destino local /onvif/deviceio_service: o Onvier solicita x=-0.2, y=0.0. Stop continua encerrando a conexão sem cabeçalho, inclusive no cliente que move a câmera. Logo exigir especificamente StopResponse bloqueava o nosso teste antes de qualquer movimento. Não é evidência de ausência de PTZ. O log não contém o corpo do pedido alternativo de parada do Onvier.

O Jortan 2.1 aceita como preflight a parada equivalente ContinuousMove com PanTilt x=0,y=0, apenas após resposta válida. Prioriza o endereço anunciado e mantém velocidade solicitada conservadora 0,1. A opção explícita por pressão renova comandos com timeout solicitado PT2S e limite local 5 s. Um comando pendente impede novos envios; soltar cancela renovação e envia parada após o último movimento. O tooltip do nosso botão passa a não disputar a pressão longa com o gesto de movimento.

O usuário relatou pausas no Onvier e continuidade no Yoosee original. Os tempos de resposta de 2–5,7 s do log incluem filas/processamento do cliente; não são uma medição isolada da rede e não provam a causa dos trancos. Não usamos informações do dispositivo externo de demonstração para este ajuste. As seções anteriores registram etapas históricas da investigação; a regra de parada agora inclui a equivalência ONVIF confirmada por resposta.
