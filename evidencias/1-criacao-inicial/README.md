# Cenário 1 · Criação inicial

> Executar a pipeline para criar o ambiente do zero: Terraform provisiona a infraestrutura e o Ansible prepara o sistema, instala dependências, Docker e os contêineres.

## Situação

O ambiente da feira já está no ar (https://34-73-148-18.sslip.io). Criá-lo do zero pelo GitHub exige destruí-lo antes (`acao = desativar`), o que **troca a URL pública** (o IP reservado é liberado) e apaga a lista de tarefas. Por isso, a criação do zero pelo GitHub fica para a apresentação ou para depois da feira.

A mesma rotina que a pipeline executa (`scripts/pipeline-gcp.sh planejar` → `provisionar` → `implantar`) já criou o ambiente do zero **duas vezes**, em projetos diferentes. A última foi num projeto temporário em 25/11/2026, sem tocar no ambiente da feira.

## Como executar pela pipeline

| Parâmetro | Valor |
| --- | --- |
| acao | `provisionar_e_implantar` |
| environment | `dev` |
| instance_name | `todo-pm04` |
| instance_type | `e2-micro` |
| docker_tag | _(vazio = commit)_ |
| update_os | `false` |
| extra_packages | _(vazio)_ |

Pré-condição: projeto GCP sem as VMs. Na criação do zero, a pipeline liga sozinha o Cloud NAT do banco para que a VM nova baixe o Docker (`NAT do banco: true (VM do banco: ainda não existe)`). No fim da mesma execução, o passo 4 desliga o NAT, para que a reexecução com os mesmos parâmetros (cenário 3) mostre `No changes`.

## Resultado do ciclo em projeto temporário (25/11/2026)

| Etapa | Resultado |
| --- | --- |
| `provisionar` (Terraform apply + Ansible `configurar.yml`) | **26 recursos criados**; Docker, Compose, swap e disco de dados configurados; `failed=0` nas duas VMs |
| `preparar`, segunda vez | `changed=0`: idempotente |
| `implantar` (Ansible `implantar.yml`) | MongoDB, Caddy, frontend e API no ar com HTTPS |
| `nat desligar` e `preparar`, terceira vez | 2 recursos removidos; `changed=0` sem internet no banco |
| `aceite` | Aprovado |
| `desativar` | Backup final copiado; 24 recursos destruídos |

Detalhes no [relatório de validação](../../docs/relatorio-validacao.md#ciclo-completo-em-projeto-temporário-2511-2150-a-2221).

## Execução pelo GitHub Actions

- **Link:** _a preencher quando executado_
