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
