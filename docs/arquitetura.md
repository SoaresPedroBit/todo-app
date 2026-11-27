# Arquitetura · ToDo App na Google Cloud

Arquitetura da implantação para a Feira de Profissões, conforme o [escopo](escopo.md).
A versão local em LocalStack, mantida como plano B, está em [localstack/arquitetura.md](localstack/arquitetura.md).

## 1. Decisões

| Decisão | Escolha | Por quê |
| --- | --- | --- |
| Provedor | Google Cloud, projeto exclusivo | Azure for Students e Oracle Cloud não liberaram conta; a AWS grátis só vale para conta nova. A GCP tem cota permanente para VMs pequenas. |
| Região | `us-east1` | A cota grátis só existe em três regiões dos EUA. Latência maior que São Paulo, aceitável para uma lista de tarefas. |
| VMs | 2 × `e2-micro` (1 GB), Ubuntu 24.04 | Menor máquina que atende; medido em uso (seção 7). |
| Acesso administrativo | SSH por Identity-Aware Proxy | Porta 22 fechada na internet, sem depender do IP de quem administra. |
| Ferramentas | **Terraform** cria, **Ansible** configura e sobe os contêineres, **Docker Compose** os descreve; Bash e GitHub Actions orquestram | Cada ferramenta com um papel. Terraform e Ansible rodam em contêiner: a equipe só instala Docker, Git, Node e gcloud. |

## 2. Diagnóstico do ponto de partida (escopo, etapa 1)

O repositório original foi executado com Docker Compose como referência. O que precisava mudar, e o que foi feito:

| Como estava | Como ficou |
| --- | --- |
| Frontend chamava `http://localhost:5000` | Caminhos relativos; o Nginx encaminha `/todos`, `/todos/:id` e `/health` à API, com os mesmos métodos e caminhos |
| Usuário e senha `root` do banco fixos no código | Conexão lida de arquivo de segredo; usuário próprio `todo_app`, só com `readWrite` em `todo-app` |
| Compose publicava as portas do banco e da API | Só 80/443, na VM da aplicação |
| Sem volume nomeado | Disco separado para os dados |
| `cors()` aberto | Desligado; mesma origem |
| API desistia se o banco não estivesse pronto | Novas tentativas, `/health` com ping no banco e resposta 503 enquanto ele não volta |
| `mongo:latest` | `mongo:7.0` fixo |
| Teste do frontend quebrado | Testes reais do fluxo |
| Sem CI/CD | Workflows de validação, ciclo local e nuvem |

## 3. Visão geral

```mermaid
flowchart LR
    V[Visitante] -->|HTTPS 443, HTTP 80 redireciona| APP
    ADM[Equipe] -->|SSH por IAP, login Google| APP
    ADM -->|SSH por IAP| DB
    subgraph VPC["VPC todo-vpc"]
      subgraph PUB["todo-publica 10.10.1.0/24"]
        APP["todo-app · 10.10.1.10 + IP público<br/>Caddy → Nginx + React → API Express"]
      end
      subgraph PRIV["todo-privada 10.10.2.0/24"]
        DB["todo-db · 10.10.2.10, SEM IP público<br/>MongoDB 7 autenticado"]
        D[("Disco de dados 10 GB")]
      end
      APP -->|27017, só da conta de serviço da app| DB
      DB --- D
    end
    subgraph SVC["Serviços do Google, por acesso privado"]
      SM[Secret Manager]
      AR[Artifact Registry]
      GCS[(Cloud Storage: backups)]
    end
    APP -.-> SM
    APP -.-> AR
    DB -.-> SM
    DB -.-> AR
    DB -.->|a cada 6 h| GCS
```

O Nginx entrega a interface e encaminha `/todos`, `/todos/:id` e `/health` à API no mesmo endereço. Só a API acessa o MongoDB. O fluxo funcional é o da seção 6 do escopo.

## 4. Segurança (REQ-02, REQ-03)

- **Entradas permitidas, só três:** 80/443 públicas na VM da aplicação; 27017 no banco, vinda da conta de serviço da aplicação; 22 nas duas VMs, vinda somente da faixa do IAP (35.235.240.0/20). O resto é recusado pela VPC.
- **Banco:** sem IP público, MongoDB escutando só em 10.10.2.10, e uma regra `iptables` na própria VM repete a restrição.
- **Privilégio mínimo:** uma conta de serviço por VM. A aplicação lê só a própria senha. O banco lê as duas, e no bucket cria e lê backups, sem sobrescrever nem apagar.
- **Segredos:** gerados na máquina de quem administra (`.local/`, fora do Git), enviados ao Secret Manager por stdin e gravados nas VMs em arquivos 0400. Não entram no código, no estado do Terraform, na linha de comando nem nos logs; o aceite procura os valores reais.
- **HTTPS:** Caddy com certificado Let's Encrypt, renovação automática, redirecionamento 308 e HSTS. O endereço é `<ip>.sslip.io`, um DNS público gratuito que aponta para o próprio IP.
- **GitHub Actions sem chave de nuvem:** identidade por OIDC ([infra/gcp-ci](../infra/gcp-ci/main.tf)), limitada a um repositório, ao branch `main` e a execução manual. Cria, altera e remove os recursos do projeto (VMs, rede, firewall, discos, segredos, registro e bucket), mas não muda o IAM do projeto. A chave SSH fica em um *secret* do repositório.

## 5. Persistência, backup e restauração (REQ-04)

| Item | Como |
| --- | --- |
| Dados | Disco separado em `/mnt/mongo-data`. Se ele não montar, o Docker não sobe, para o banco não iniciar vazio no disco errado. Só é formatado um disco sem sistema de arquivos. |
| Backup | A cada 6 h, e antes de deploy do banco, limpeza, restauração, pausa e desativação. Retenção de 30 dias no bucket, com as 5 cópias mais recentes no disco. `backup` também copia para `.local/backups/`. |
| Restauração de teste | MongoDB temporário, sem rede. A produção não é tocada. |
| Restauração real | Pede `RESTAURAR` e faz um backup antes. |

## 6. Automação e infraestrutura como código

| Camada | Ferramenta | Onde |
| --- | --- | --- |
| Criar rede, VMs, discos, permissões | Terraform | `infra/gcp/` |
| Configurar as VMs: Docker, swap, disco de dados, serviço de boot | Ansible | `infra/ansible/` |
| Implantar: senhas, versões, login no registro e subida dos contêineres | Ansible + Docker Compose | `infra/ansible/implantar.yml`, `deploy/*/compose.yaml` |
| Operar e recuperar: status, logs, backup, restauração | `ops.sh` | `deploy/` |
| Orquestrar as rotinas | `pipeline-gcp.sh` e GitHub Actions | `scripts/`, `.github/workflows/` |

O Ansible alcança as VMs por dentro do IAP e é idempotente: `preparar --check` mostra o que mudaria sem mudar. Ele só formata disco sem sistema de arquivos; na dúvida, para.

| Operação do escopo | Rotina (`./scripts/pipeline-gcp.sh …`) |
| --- | --- |
| Validar e planejar | `validar` · `planejar` |
| Provisionar e configurar | `bootstrap` (uma vez) · `provisionar` (aplica o plano exibido e roda o Ansible) · `preparar [--check]` |
| Implantar e atualizar | `implantar` (versão = commit) · `implantar <versão>` (rollback) · `versoes` |
| Manter e diagnosticar | `status` · `logs-app` · `logs-banco` · `reiniciar-app` · `reiniciar-banco` |
| Proteger e recuperar | `backup` · `backups` · `restaurar-teste` · `restaurar` |
| Desativar | `pausar` · `retomar` · `nat` · `desativar` |

- **Estado do Terraform:** bucket privado e versionado. Para recuperar, restaure a versão anterior do objeto `todo-app/default.tfstate`.
- **Versões:** imagens com o SHA do commit no Artifact Registry. A imagem do banco só muda quando `banco-de-dados/` muda, então atualizar a aplicação não reinicia o MongoDB.
- **Workflows:** `ci.yml` (validação e integração), `localstack.yml` (ciclo completo local) e `gcp.yml` (plano, criação ou alteração das VMs, implantação, rollback, aceite e desativação na GCP). O tipo das VMs é uma entrada do `gcp.yml` (`instance_type`).

## 7. Dimensionamento medido (24/11/2026)

| VM | Memória usada | Swap | Disco de sistema |
| --- | --- | --- | --- |
| `todo-app` | 501 de 953 MB | 18 MB | 52% |
| `todo-db` | 365 de 953 MB | 143 MB | 60% |

Medido em repouso, após o aceite. A margem é pequena: um healthcheck pesado chegou a travar a VM do banco durante um teste (causa e correção no [relatório](relatorio-validacao.md)). O MongoDB usa cache fixo de 0,25 GB e cada VM tem 1 GB de swap. **Não foi feito teste de carga.** Se a feira exigir mais, rode a pipeline com `instance_type` = `e2-small` (sai da cota grátis).

## 8. Limitações e premissas

| Item | Impacto e tratamento |
| --- | --- |
| Data, público e domínio não informados no escopo | Premissa: apresentação na semana de 30/11/2026, algumas dezenas de visitantes. Confirmar com a organização. |
| Uma VM por função | Se uma cair, o site para. Reinício automático dos serviços e backup; sem alta disponibilidade, o que o escopo não pede. |
| `sslip.io` é de terceiros | Se sair do ar, o endereço não resolve. Alternativa: domínio próprio em `site_address`. |
| Lista compartilhada | Como no escopo; use `limpar-lista` antes de cada apresentação. |
| NAT desligado | O banco não baixa pacotes da internet. Para atualizar: `nat ligar`, atualizar, `nat desligar`. |
| Recriar tudo muda o IP | `desativar` libera o IP. Não faça isso depois de divulgar o endereço. |

### Dados a confirmar com a organização (escopo, seções 11 e 13)

| Dado | Hipótese usada | Confirmado por / em |
| --- | --- | --- |
| Data e duração da apresentação | Semana de 30/11/2026, 1 dia | *a preencher* |
| Visitantes simultâneos | Algumas dezenas | *a preencher* |
| Domínio próprio | Não há; `sslip.io` | *a preencher* |
| Responsável pela conta da nuvem | Dono do projeto na GCP | *a preencher* |
| Responsável pelo repositório e *secrets* | Dono do fork | *a preencher* |
| Responsável pela operação na feira | Alunos, com o manual | *a preencher* |

### Marcos

| Marco | Data |
| --- | --- |
| Publicação na nuvem | 24/11/2026 |
| Ciclo completo de criação e desativação em projeto temporário | 25/11/2026 |
| Ensaio conduzido pelos alunos | *até 28/11/2026, a confirmar* |
| Apresentação | *a confirmar* |
| Desativação | *até o dia seguinte à apresentação* |

## 9. Custos (ACE-09)

**Fonte:** catálogo oficial de preços da Google (Cloud Billing Catalog API), consultado em **24/11/2026**, em **USD**, região `us-east1`, sob demanda, sem impostos. Cota grátis: [documentação do Free Tier](https://docs.cloud.google.com/free/docs/free-cloud-features).

**Premissas:** mês de 730 h; discos `pd-standard`; período de 8 dias (192 h): 6 de preparação e ensaio, 1 de evento e 1 de encerramento.

### Preço cheio (sem cota grátis)

| Recurso | Preço | Mês | Período |
| --- | --- | --- | --- |
| 2 VMs `e2-micro` (0,25 vCPU + 1 GB) | US$ 0,00838/h cada¹ | 12,23 | 3,22 |
| Discos, 30 GB | US$ 0,04/GB-mês | 1,20 | 0,32 |
| IP público em uso | US$ 0,005/h | 3,65 | 0,96 |
| 2 segredos | US$ 0,06/mês cada | 0,12 | 0,03 |
| Imagens, até 0,5 GB | US$ 0,10/GB-mês | 0,05 | 0,01 |
| Backups, menos de 0,1 GB | US$ 0,02/GB-mês | < 0,01 | < 0,01 |
| Tráfego de saída, 1 GB² | US$ 0,19/GB (América do Sul) | 0,19 | 0,19 |
| Logs no Cloud Logging, menos de 50 GB | US$ 0,50/GB | 0 | 0 |
| DNS (`sslip.io`) e certificado (Let's Encrypt) | gratuitos | 0 | 0 |
| Domínio próprio | não usado | 0 | 0 |
| **Total** | | **≈ 17,44** | **≈ 4,73** |

² A primeira visita transfere cerca de 89 KB (medido em 25/11/2026), então 1 GB cobre por volta de 12 mil primeiras visitas.

¹ 0,25 × US$ 0,02181159 (núcleo E2) + 1 × US$ 0,00292353 (GB de memória).

### Com a cota grátis, que não expira

| Recurso | Cota por mês | Mês inteiro | Período |
| --- | --- | --- | --- |
| VMs | horas de `e2-micro` iguais às do mês | 6,12 (as 730 h excedentes) | **0** (384 h) |
| Discos | 30 GB | 0 | 0 |
| IP público em uso | 721 h | ≈ 0 | 0 |
| Segredos, imagens, backups | 6 versões · 0,5 GB · 5 GB | 0 | 0 |
| Tráfego de saída | 1 GB | 0 | 0 |
| Logs | 50 GB | 0 | 0 |
| **Total** | | **≈ US$ 6,12** | **≈ US$ 0** |

**O que pode variar:**

- **IP com a VM desligada custa US$ 0,01/h** (≈ US$ 0,24/dia). Pausar sai mais caro do que manter ligado dentro da cota.
- **NAT ligado:** US$ 0,0014/h por VM + US$ 0,005/h do IP + US$ 0,045/GB. Fica desligado.
- **Tráfego de saída:** 1 GB/mês grátis; acima disso, US$ 0,19/GB para a América do Sul.
- A cota é da conta de faturamento: outro projeto com `e2-micro`, disco ou IP a divide.
- O valor final é cobrado em reais, pela cotação da Google e com impostos.

**Proteção:** orçamento de R$ 1/mês para o projeto, com avisos em 20%, 50% e 100% do gasto e quando a previsão do mês passa de 100%. Ele avisa, mas não bloqueia.

**Dados e cópias:** disco de dados de 10 GB; backups por 30 dias no bucket, 5 cópias no disco e cópia em `.local/backups/`. Depois de `desativar`, só a cópia local permanece.

**Depois do evento:** após `desativar`, resta o bucket do estado (poucos KB). Apagar o projeto encerra tudo.

**GitHub Actions:** gratuito em repositório público, com os executores padrão.
