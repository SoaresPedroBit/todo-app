# ToDo App

Aplicação de lista de tarefas usada nos laboratórios de Engenharia de Software do professor Laércio. Permite cadastrar, listar, concluir, reabrir e excluir tarefas.

Este repositório contém a aplicação **e** a implantação pedida no [escopo da Feira de Profissões](escopo.pdf) ([versão editável](docs/escopo.md)). A aplicação e o banco rodam em VMs distintas, a infraestrutura é criada com **Terraform**, configurada com **Ansible** e operada por pipelines. O ambiente da feira roda na **Google Cloud**; uma versão local na **AWS emulada pelo LocalStack** serve de plano B.

| Documento | Conteúdo |
| --- | --- |
| [docs/arquitetura.md](docs/arquitetura.md) | Arquitetura, decisões, segurança, backups, limitações e **custos** |
| [docs/manual-alunos.md](docs/manual-alunos.md) | **Manual de operação**: subir, verificar, atualizar, recuperar e desligar |
| [docs/relatorio-validacao.md](docs/relatorio-validacao.md) | Evidências dos critérios de aceite (ACE-01 a ACE-10) |
| [evidencias/](evidencias/README.md) | **Evidências do PM-04**: cenários 1, 2 e 3 e validação da demanda |
| [docs/localstack/](docs/localstack/arquitetura.md) | Arquitetura, manual e relatório do ambiente local |

## Colocar no ar (Google Cloud)

Pré-requisitos: Docker Desktop, Git Bash, Node.js 22, Google Cloud CLI autenticado e `infra/gcp/terraform.tfvars`. O passo a passo, com os resultados esperados, está no [manual](docs/manual-alunos.md).

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
