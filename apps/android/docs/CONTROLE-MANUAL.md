# Teste manual Yoosee — versão 2.1

Solicitado explicitamente pelo usuário em 06/11/2026 depois de falharem GetConfigurationOptions, GetNode e GetNodes nas três serializações testadas. O aplicativo original gira a câmera; isso não identifica o protocolo que ele usa.

1. Conecte o vídeo, permaneça na aba Ao vivo e toque em **Testar compatibilidade Yoosee**. Este caminho obtém perfis reais por ONVIF e não repete as consultas de capacidades que já falharam. Não envia movimento nem Stop automaticamente.
2. O teste usa o token do perfil recebido e endereços no mesmo IP, priorizando o serviço PTZ anunciado. Na câmera do usuário, o Onvier confirmou ContinuousMove em /onvif/deviceio_service na porta 5000. **Ativar teste de movimento** solicita primeiro Stop; se ele falhar, testa ContinuousMove com velocidade zero nos formatos padrão/mínimo. Nenhuma velocidade diferente de zero é enviada nessa etapa. Apenas uma resposta SOAP válida arma as setas. Se todas as paradas falharem, selecione outro teste no menu e tente ativar novamente.
3. Comece com um toque curto: velocidade solicitada de 0,1 e timeout de 300 ms, sem URI de espaço inventado. Depois, se desejar, ative **Segurar para mover**. Nesse modo o app renova ContinuousMove enquanto segura, com timeout solicitado de 2 segundos e limite de 5 segundos por pressão. Soltar/cancelar solicita a operação de parada confirmada. Nunca há mais de um movimento em andamento nem repetição automática de movimento recusado. Se as respostas demorarem mais que o timeout, ainda podem ocorrer pausas; não há garantia de fluidez antes de testar na câmera. Zoom físico não faz parte deste modo.
4. Ao sair da aba, trocar perfil, sair do app ou receber erro, o teste é desativado. É necessário ativar novamente. Parar permanece disponível para solicitar parada mesmo sem gesto em andamento.
5. Em caso de erro, abra Diagnóstico e use **Copiar resumo curto**. O arquivo completo também permanece disponível. Não envie senha.

O formato mínimo usa envelope SOAP 1.2 com prefixo ptz, filhos de movimento no formato comunitário Yoosee, Content-Length e Connection: close, sem WSSE/SOAPAction extras. Desde a 2.0.1 inclui Action, To e um MessageID único por pedido em WS-Addressing 2004/08, seguindo o exemplo executável da referência comunitária. O formato padrão PTZ usa 2005/08. Se o serviço exigir HTTP Basic/Digest por desafio, usa as credenciais locais configuradas, sem retê-las nos eventos. Uma alternativa padrão preserva WSSE, namespace e o formato aceito nas consultas. Nenhuma tentativa automática de outro formato é feita para um movimento.

Referência comunitária usada para o formato, sem garantia de compatibilidade nesta unidade: https://github.com/victorbillyph/Yoosee-camera-documentation . O driver e os testes desta entrega foram implementados no projeto; a referência não substitui teste real.

## Parada por velocidade zero

O registro local do Onvier mostrou ContinuousMoveResponse em /onvif/deviceio_service, mas resposta HTTP vazia para Stop, inclusive na alternativa que o Onvier tentou. O corpo dessa alternativa não consta no registro. Portanto não afirmamos reproduzir exatamente o pedido do Onvier. Usamos a equivalência normativa do ONVIF PTZ: velocidade zero para os eixos especificados os faz parar, como Stop. Uma resposta vazia nunca é tratada como confirmação de parada.

Referência: ONVIF PTZ Service, seção 5.3.3, e documentação oficial do driver Milestone: https://doc.milestonesys.com/xprotect/onvif-driver-overview/v1.27/en/why-the-onvif-driver-does-not-send-ptz-stop-command-

Movimento no Onvier foi confirmado pelo usuário, com pausas durante a pressão; no Yoosee original ele relata movimento contínuo. Funcionamento e fluidez do Jortan 2.1 permanecem pendentes de teste físico.
