JORTAN PONTE 1.2 — ENDEREÇO FIXO GRATUITO

O Tailscale é instalado somente no notebook. No iPhone, use o Safari e sua senha remota do Jortan. Não é necessário instalar Tailscale no iPhone nem comprar domínio.

1. Feche a janela da ponte antiga. Baixe o Tailscale para Windows pela página oficial: https://tailscale.com/download/windows
2. Instale e entre na sua conta do plano Personal (uso pessoal gratuito). O login ocorre no Tailscale; não informe senha da conta no Jortan nem no chat.
3. Extraia todo o pacote Jortan e execute INICIAR-COM-ENDERECO-FIXO.cmd. O painel local abre automaticamente e reutiliza a configuração protegida da câmera.
4. Se aparecer Autorizar endereço fixo no Tailscale, abra esse botão e conclua a autorização do Funnel/HTTPS. Volte ao painel. Caso o endereço ainda não apareça, feche e abra novamente o atalho de endereço fixo.
5. Copie o HTTPS mostrado. Abra no Safari do iPhone ou salve na aba Remoto do Jortan Viewer Android 2.5. Entre com a senha REMOTA que você já usa. No Safari: Compartilhar > Adicionar à Tela de Início.

O endereço usa o domínio fornecido pelo Tailscale, no formato nome-do-notebook.nome-da-rede.ts.net. Ele permanece igual enquanto o dispositivo e os nomes da rede/notebook forem mantidos. Renomear ou recriar o dispositivo/rede pode alterar o endereço.

O notebook precisa ficar ligado, com a tampa aberta, na rede da câmera, conectado ao Tailscale e com a ponte aberta. Fechar a ponte encerra o Funnel criado por este atalho. O programa usa configuração em primeiro plano, sem apagar ou substituir outros serviços Funnel existentes.

O Funnel está em beta e tem limites de banda não ajustáveis; não é uma promessa de transmissão ilimitada ou de disponibilidade contínua. O plano Personal é gratuito para uso pessoal conforme informações oficiais consultadas em 12/11/2026:
https://tailscale.com/pricing
https://tailscale.com/docs/features/tailscale-funnel

Se o Tailscale não estiver instalado/conectado, o painel informa o que falta. Se houver conflito com outro serviço na porta 443, o Jortan não o apaga. Para usar o modo temporário anterior, feche a ponte e execute INICIAR-PONTE.cmd. Esse outro modo continua gerando URL temporária Cloudflare.

Nenhuma conta, domínio ou endereço real foi criado automaticamente neste pacote. Os testes usaram CLI simulada e vídeo de teste; a ativação real depende da sua conta e do seu Windows.
