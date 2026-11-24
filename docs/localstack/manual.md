# Manual de operação · ToDo App na Feira

> **Ambiente alternativo.** A entrega principal roda na Google Cloud: [arquitetura](../arquitetura.md), [manual](../manual-alunos.md), [relatório](../relatorio-validacao.md). Este documento descreve a versão local, sem custo, mantida como plano B.

Guia para a equipe colocar o ToDo App no ar, verificar, atualizar, recuperar e desligar.
Todos os comandos rodam no **Git Bash** (Windows) ou em um terminal Linux/macOS, **na pasta do repositório**.

> **Regra de ouro:** reiniciar serviço **não apaga dados**. Só três rotinas mexem nos dados, e as três pedem uma palavra de confirmação e fazem um backup antes: `limpar-lista`, `restaurar` e `desativar`.

## 0. Pré-requisitos (uma vez)

1. **Docker Desktop** instalado e aberto (containers Linux), com pelo menos 8 GB de RAM livres.
2. **Git** (inclui o Git Bash) e **Node.js 22**, usado pelo teste de fumaça.
3. As portas **80 e 443** livres. Se o ToDo App local estiver rodando, pare com `docker compose down`.
4. Clonar o repositório e abrir o Git Bash na pasta `todo-app`.

Nada mais é necessário: o Terraform, o LocalStack e as ferramentas da AWS rodam em contêineres.

## 1. Colocar no ar (primeira vez ou depois de desligar)

```bash
./scripts/pipeline.sh ciclo-completo
```

Esse comando faz, em ordem:

| Etapa | O que acontece | Resultado esperado |
| --- | --- | --- |
| `subir-localstack` | sobe a "nuvem" local e cria as senhas | `[OK] LocalStack 4.14…`, `[OK] todo/mongo-…-password` |
| `provisionar` | Terraform cria VPC, sub-redes, Security Groups, 2 EC2, EBS, S3, IAM e as 2 VMs | `Apply complete!`, `[OK] todo-vm-db pronta`, `[OK] todo-vm-app pronta` |
| `implantar` | constrói as imagens, implanta o banco e a aplicação e testa pelo HTTPS | `[OK] Versão <sha> no ar em https://localhost` |
| `aceite` | roda todos os critérios de aceite e salva o relatório | `Evidências salvas em .local/evidencias/aceite-….log` |

A primeira execução leva de 10 a 15 minutos, porque baixa as imagens. As seguintes são mais rápidas.

Quem preferir fazer etapa por etapa (por exemplo, para ver o plano antes de criar):

```bash
./scripts/pipeline.sh subir-localstack
./scripts/pipeline.sh planejar      # mostra o que o Terraform VAI fazer, sem fazer
./scripts/pipeline.sh provisionar   # executa
./scripts/pipeline.sh implantar
```

### Abrir no navegador

- Endereço: **https://localhost**
- O navegador vai avisar que o certificado não é confiável, porque ele foi emitido pela CA interna do ambiente. Para remover o aviso:
  ```bash
  ./scripts/pipeline.sh exportar-ca
  ```
  e rode o comando `certutil …` que ele mostra (Windows). Depois, feche e abra o navegador.

### Abrir em outro dispositivo da mesma rede (celular dos visitantes)

1. Descubra o IP da máquina na rede da feira (`ipconfig`, linha "Endereço IPv4"), por exemplo `192.168.0.42`.
2. Provisione com esse nome e reimplante:
   ```bash
   SITE_ADDRESS=192-168-0-42.sslip.io ./scripts/pipeline.sh provisionar
   SITE_ADDRESS=192-168-0-42.sslip.io ./scripts/pipeline.sh implantar
   ```
3. No celular, abra `https://192-168-0-42.sslip.io` e aceite o aviso de certificado.
4. Se não abrir, libere as portas 80/443 no Firewall do Windows para a rede privada.

> Use sempre o mesmo `SITE_ADDRESS` nos comandos seguintes, ou exporte uma vez: `export SITE_ADDRESS=192-168-0-42.sslip.io`.

## 2. Antes de cada apresentação

```bash
./scripts/pipeline.sh status          # tudo "healthy"? saúde "ok"?
./scripts/pipeline.sh limpar-lista    # digite LIMPAR -> lista de demonstração nova
```

`limpar-lista` faz backup da lista atual antes de apagá-la. Se foi sem querer, veja a seção 5.

Avise os visitantes: **a lista é compartilhada**. Todos veem e podem concluir ou excluir as tarefas uns dos outros, então não devem digitar dados pessoais.

## 3. Verificar e diagnosticar

| Quero… | Comando |
| --- | --- |
| Ver se está tudo de pé | `./scripts/pipeline.sh status` |
| Logs da aplicação (todos os serviços, 200 linhas) | `./scripts/pipeline.sh logs-app` |
| Logs só da API, 50 linhas | `./scripts/pipeline.sh logs-app backend 50` |
| Logs do banco | `./scripts/pipeline.sh logs-banco 100` |
| Saúde da API e do banco | abrir `https://localhost/health` → `{"status":"ok","api":"ok","banco":"ok"}` |
| Provar que o banco está isolado | `./scripts/pipeline.sh verificar-isolamento` |

### Problemas comuns

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| Página mostra "Não foi possível falar com o servidor" | API sem banco | `status`. Se o MongoDB não estiver `healthy`: `reiniciar-banco`. Depois `logs-banco`. |
| `/health` mostra `"banco":"desconectado"` | Banco reiniciando ou parado | Aguarde 30 s (a API reconecta sozinha) ou rode `reiniciar-banco`. |
| Navegador não abre `https://localhost` | Docker Desktop fechado, porta 443 ocupada ou VM parada | Abra o Docker Desktop e rode `status`. Se a VM não existir: `provisionar` e depois `implantar`. |
| Erro "infraestrutura não provisionada" | VMs não existem | `provisionar`, depois `implantar`. |
| Depois de reiniciar o computador, nada funciona | O LocalStack perdeu o estado (edição gratuita) | `./scripts/pipeline.sh provisionar` e depois `implantar`. **Os dados continuam lá**, no volume do banco. |
| `bind: address already in use` na porta 80/443 | Outro programa usando a porta | Pare o outro programa (ou o `docker compose` local) e repita. |
| Aviso de certificado no navegador | CA interna | Seção 1, "Abrir no navegador". |
| Algo estranho só na aplicação | Contêiner travado | `./scripts/pipeline.sh reiniciar-app` (ou `reiniciar-app backend`) |

## 4. Atualizar a aplicação e voltar versão

```bash
git pull                                # pega a versão nova do código
./scripts/pipeline.sh implantar         # constrói e implanta; versão = commit atual
./scripts/pipeline.sh versoes           # versões publicadas e histórico
./scripts/pipeline.sh implantar abc1234 # ROLLBACK: volta para a versão abc1234
```

- A atualização **não apaga tarefas**. O banco só é reiniciado se a pasta `banco-de-dados/` mudou, e mesmo assim os dados ficam no volume.
- O rollback volta só a aplicação (frontend e API). Os dados do banco não "voltam no tempo"; para isso existe a seção 5.
- Se o teste no final do `implantar` falhar, rode o rollback para a última versão boa, que aparece em `versoes`.

## 5. Backup e recuperação de dados

| Quero… | Comando |
| --- | --- |
| Backup agora (S3 + cópia em `.local/backups/`) | `./scripts/pipeline.sh backup` |
| Ver backups disponíveis | `./scripts/pipeline.sh backups` |
| **Testar** um backup sem mexer na demonstração | `./scripts/pipeline.sh restaurar-teste` (o mais recente) ou `restaurar-teste <arquivo>` |
| **Voltar** a lista para um backup | `./scripts/pipeline.sh restaurar <arquivo>` e digite RESTAURAR |

- Backups automáticos: a cada 6 horas, e também antes de cada atualização, limpeza, restauração ou desativação.
- Exemplo: depois de um `limpar-lista` acidental, rode `backups`, pegue o arquivo `…-pre-reset.archive.gz` mais recente e execute `restaurar <esse-arquivo>`.
- Se o LocalStack reiniciou e o S3 ficou vazio, as cópias continuam em `.local/backups/`.

## 6. Depois da feira: desligar

```bash
./scripts/pipeline.sh desativar        # digite DESTRUIR
./scripts/pipeline.sh parar-localstack
```

`desativar` faz um **backup final** em `.local/backups/` e depois remove VMs, rede, volume de dados, bucket e recursos AWS (`terraform destroy`). No fim, ele lista o que **permanece** na máquina:

| Permanece | Para remover |
| --- | --- |
| Backups exportados (`.local/backups/`) | apagar a pasta, se não quiser guardar as tarefas |
| Senhas (`.local/segredos/`) | apagar a pasta |
| Cópias do estado do Terraform (`.local/estado-backups/`) | apagar a pasta |
| Imagens no registro local | `docker compose -f infra/localstack/compose.yaml down -v` |

**Custo de nuvem: nenhum.** O ambiente é 100% local, então nada continua gerando cobrança.

## 7. Onde fica cada coisa

| Caminho | Conteúdo |
| --- | --- |
| `scripts/pipeline.sh` | todas as rotinas deste manual |
| `infra/terraform/` | infraestrutura como código (AWS no LocalStack + VMs) |
| `infra/localstack/compose.yaml` | LocalStack e registro de imagens |
| `deploy/app`, `deploy/db` | arquivos que vão para cada VM (`ops.sh`, Compose, Caddyfile) |
| `.local/` (não versionado) | senhas, backups exportados, evidências, histórico de versões |
| `docs/arquitetura.md` | decisões, diagramas, limitações e custos |
| `docs/relatorio-validacao.md` | evidências dos critérios de aceite |
