# ToDo App

Aplicação de lista de tarefas usada nos laboratórios de Engenharia de Software do professor Laércio. Permite cadastrar, listar, concluir, reabrir e excluir tarefas.

Este repositório contém a aplicação **e** a implantação pedida no [escopo da Feira de Profissões](escopo.pdf) ([versão editável](docs/escopo.md)), que é o documento de demanda do **PM-04 (Projeto Final: automação de infraestrutura com Terraform, Ansible e CI/CD)**. A aplicação e o banco rodam em VMs distintas, a infraestrutura é criada com **Terraform**, configurada com **Ansible** e operada pela pipeline do **GitHub Actions**. O ambiente da feira roda na **Google Cloud**; uma versão local na **AWS emulada pelo LocalStack** serve de plano B.

| Documento | Conteúdo |
| --- | --- |
| [entrega/PM04-entrega.pdf](entrega/PM04-entrega.pdf) | Documento de entrega do PM-04: demanda, arquitetura, requisitos e evidências |
| [docs/arquitetura.md](docs/arquitetura.md) | Arquitetura, decisões, segurança, backups, limitações e **custos** |
| [docs/manual-alunos.md](docs/manual-alunos.md) | **Manual de operação**: subir, verificar, atualizar, recuperar e desligar |
| [docs/relatorio-validacao.md](docs/relatorio-validacao.md) | Evidências dos critérios de aceite (ACE-01 a ACE-10) e dos cenários do PM-04 |
| [docs/localstack/](docs/localstack/arquitetura.md) | Arquitetura, manual e relatório do ambiente local |

## Pipeline do PM-04 (GitHub Actions)

Toda mudança na nuvem passa pelo workflow [`.github/workflows/gcp.yml`](.github/workflows/gcp.yml): **Actions > GCP > Run workflow**. Ele executa em sequência o **Terraform** (`init`, `plan` e o `apply` do plano exibido) e o **Ansible** (`configurar.yml` e depois `implantar.yml`). A execução para no primeiro erro, anexa os registros como artefato e mostra um resumo na própria página: parâmetros, plano do Terraform e `PLAY RECAP` do Ansible.

| Parâmetro | Exemplo | O que muda de fato |
| --- | --- | --- |
| `acao` | `planejar`, `provisionar_e_implantar`, `rollback`, `aceite`, `desativar` | Qual rotina roda |
| `environment` | `dev` / `homolog` / `prod` | Etiqueta `environment` das duas VMs (Terraform, alteração no lugar) |
| `instance_name` | `todo-pm04` | Etiqueta `instance_name` das VMs (Terraform, no lugar). Os nomes `todo-app` e `todo-db` são fixos: renomear uma VM na GCP obriga a recriá-la |
| `instance_type` | `e2-micro`, `e2-small` | Tipo das duas VMs. O Terraform desliga, troca e religa cada VM, sem recriar: disco, IP e dados ficam |
| `docker_tag` | vazio ou `58e7363` | Versão das imagens implantadas pelo Ansible. Vazio = último commit que alterou `frontend/` ou `backend/`. Uma tag já publicada é reaproveitada, não reconstruída. No `rollback`, a versão a voltar |
| `update_os` | `true` / `false` | O Ansible sempre lista as atualizações pendentes; com `true`, aplica (`apt dist-upgrade`) e avisa se o sistema pedir reinício |
| `extra_packages` | `curl,git,unzip` | O Ansible instala os pacotes nas duas VMs (vírgula ou espaço) |
| `confirmacao` | `DESTRUIR` | Trava da ação `desativar` |

Não há `docker_image`: as imagens deste sistema são fixas (frontend, backend e MongoDB, construídas a partir do repositório), e o que varia entre execuções é a versão, em `docker_tag`.

A VM do banco não tem IP público. A saída de internet dela (Cloud NAT) liga sozinha quando `update_os=true` ou `extra_packages` pedem pacotes, e também na criação do zero, quando é desligada no fim da mesma execução (passo 4). Sem pacotes para instalar, fica desligada.

### Cenários da apresentação

| Cenário | Como rodar (`acao = provisionar_e_implantar`) | Resultado esperado |
| --- | --- | --- |
| 1 · Criação inicial | Projeto sem recursos | `Plan: 26 to add`; Ansible com `failed=0` nas duas VMs; aplicação no ar por HTTPS; NAT desligado no passo 4 |
| 2 · Atualização | Outro `instance_type` e, no Ansible, `extra_packages` (ex.: `htop`), `update_os=true` ou nova `docker_tag` | VMs `updated in-place`; Ansible com `changed` nas tarefas pedidas |
| 3 · Reexecução | Exatamente os parâmetros do cenário 2, com `docker_tag` fixa | `No changes` no Terraform e `changed=0` no Ansible |

As execuções já feitas estão no [relatório de validação](docs/relatorio-validacao.md#cenários-do-pm-04-pelo-github).

### Pré-requisitos da pipeline (uma vez, pelo dono do projeto)

1. `./scripts/pipeline-gcp.sh bootstrap`: ativa as APIs e cria o bucket privado e versionado do estado do Terraform (`<projeto>-todo-tfstate`).
2. Aplicar [`infra/gcp-ci`](infra/gcp-ci/main.tf) na própria máquina (backend no mesmo bucket, prefixo `todo-ci`; variáveis `project_id` e `github_repository`). Ele cria a identidade OIDC do GitHub, sem chave de nuvem, limitada a este repositório, ao ramo `main` e à execução manual.
3. Em **Settings > Secrets and variables > Actions**:

| Tipo | Nome | Valor |
| --- | --- | --- |
| Variable | `GCP_PROJECT_ID` | ID do projeto na GCP |
| Variable | `GCP_WIF_PROVIDER` | saída `workload_identity_provider` do `infra/gcp-ci` |
| Variable | `GCP_SERVICE_ACCOUNT` | saída `service_account` do `infra/gcp-ci` |
| Variable | `TODO_SSH_PUB` | chave pública SSH das VMs |
| **Secret** | `TODO_SSH_KEY` | chave privada SSH das VMs (nunca no código) |

As senhas do MongoDB não são parâmetros: a pipeline as gera, guarda no Secret Manager e as VMs as leem de lá.

### Onde está cada item da estrutura sugerida no PM-04

| Sugerido | Neste repositório |
| --- | --- |
| `.github/workflows/deploy.yml` | [`.github/workflows/gcp.yml`](.github/workflows/gcp.yml) |
| `terraform/main.tf` | [`infra/gcp/`](infra/gcp): `compute.tf` (VMs e IP), `network.tf` (VPC, sub-redes, firewall e NAT), `iam.tf` (contas de serviço e segredos), `storage.tf` (disco de dados, backups e registro de imagens) |
| `terraform/variables.tf`, `outputs.tf` | `infra/gcp/variables.tf`, `infra/gcp/outputs.tf` |
| `terraform/providers.tf`, `backend.tf` | `infra/gcp/versions.tf` (provider `google` e backend `gcs`) |
| `ansible/inventory/` | [`infra/ansible/inventario.yml`](infra/ansible/inventario.yml) |
| `ansible/playbook.yml` | `infra/ansible/configurar.yml` (SO, pacotes e Docker) e `infra/ansible/implantar.yml` (contêineres) |
| `ansible/group_vars/` | `defaults/` de cada role, parâmetros da pipeline (`-e`) e saídas do Terraform |
| `roles/os_updates/` | [`roles/base`](infra/ansible/roles/base/tasks/main.yml): atualizações do SO, pacotes adicionais e swap |
| `roles/docker/` | `roles/base` (Docker e Compose) e `roles/banco` (disco de dados e dependência do serviço Docker) |
| `roles/containers/` | `roles/implantacao` (registro e arquivos), `roles/mongo` (banco) e `roles/aplicacao` (Caddy, frontend e API) |
| `evidencias/` | [`docs/relatorio-validacao.md`](docs/relatorio-validacao.md), [`entrega/`](entrega) (PDF e prints) e os artefatos de cada execução no Actions |

> `infra/terraform/` é o Terraform do **plano B local (LocalStack)**. A pipeline do PM-04 usa `infra/gcp/`.

## Rotinas pela máquina da equipe (Google Cloud)

As mesmas rotinas que a pipeline executa também rodam da máquina da equipe, úteis para operar e diagnosticar. Pré-requisitos: Docker Desktop, Git Bash, Node.js 22, Google Cloud CLI autenticado e `infra/gcp/terraform.tfvars`. O passo a passo, com os resultados esperados, está no [manual](docs/manual-alunos.md).

```bash
./scripts/pipeline-gcp.sh bootstrap      # uma vez: APIs e bucket do estado
./scripts/pipeline-gcp.sh planejar       # mostra o que será criado
./scripts/pipeline-gcp.sh provisionar    # cria as duas VMs e as configura com Ansible
./scripts/pipeline-gcp.sh implantar      # publica a aplicação com HTTPS
./scripts/pipeline-gcp.sh aceite         # evidências
./scripts/pipeline-gcp.sh desativar      # depois da feira
```

## Plano B: local (LocalStack)

Pré-requisitos: Docker Desktop, Git Bash e Node.js 22. As portas 80 e 443 precisam estar livres.

```bash
./scripts/pipeline.sh ciclo-completo   # LocalStack + Terraform + implantação + testes de aceite
```

Depois abra **https://localhost**. Para o navegador confiar no certificado, rode `./scripts/pipeline.sh exportar-ca`. Todas as rotinas estão em `./scripts/pipeline.sh ajuda` e no [manual do ambiente local](docs/localstack/manual.md).

```text
Visitante --HTTPS--> VM 1 todo-app (10.10.1.10)        VM 2 todo-db (10.10.2.10, sem IP público)
                     Caddy -> Nginx + React -> API --27017 (só da VM 1)--> MongoDB + volume EBS
                                                                          backup a cada 6 h -> S3
```

## Executar só a aplicação (desenvolvimento)

Pré-requisitos: Git e Docker com Docker Compose.

```bash
cp .env.example .env              # troque as senhas
docker compose up --build -d --wait
```

Acesse **http://localhost**. A API responde no mesmo endereço (`/todos`, `/health`); o Nginx encaminha as chamadas. O MongoDB e a API não publicam portas. Os dados ficam no volume `mongo-data`: `docker compose down` mantém os dados, e `down -v` apaga.

Testes: `cd frontend && npm test` · fluxo completo: `./scripts/smoke-test.sh http://localhost --completo`.

## Estrutura

| Pasta | Conteúdo |
| --- | --- |
| `frontend/` | Interface React servida pelo Nginx, que também encaminha `/todos` e `/health` para a API |
| `backend/` | API Node.js/Express + Mongoose (configuração por ambiente, `/health`, reconexão) |
| `banco-de-dados/` | Imagem MongoDB 7, usuário da aplicação e lista de demonstração |
| `infra/gcp/` | Infraestrutura como código da Google Cloud: rede, 2 VMs, discos, IAM, segredos e backups |
| `infra/ansible/` | `configurar.yml`: Docker, swap, disco de dados e serviço de boot. `implantar.yml`: senhas, versões e subida dos contêineres |
| `infra/gcp-ci/` | Acesso do GitHub Actions à GCP por OIDC, sem chave (aplicado pelo dono do projeto) |
| `infra/terraform/` | Infraestrutura como código: VPC, Security Groups, EC2, EBS, S3, IAM, Secrets (LocalStack) e as VMs |
| `infra/localstack/` | LocalStack 4.14 + registro de imagens |
| `infra/vm-image/` | Imagem das VMs (Docker-in-Docker + AWS CLI) |
| `deploy/` | Arquivos de cada VM: Compose, Caddyfile e `ops.sh` (status, backup, restore…; no LocalStack, também o deploy) |
| `scripts/` | `pipeline-gcp.sh` (nuvem), `pipeline.sh` (local), `smoke-test.sh`, `verificar-isolamento.sh` |
| `.github/workflows/` | `ci.yml` (validação), `localstack.yml` (ciclo completo local) e `gcp.yml` (plano, criação ou alteração das VMs, implantação, rollback, aceite e desativação na nuvem) |

Para gerar os PDFs do escopo, instale a dependência `reportlab` e execute `python scripts/render-escopo.py`.
