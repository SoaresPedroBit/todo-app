# Manual de operação · ToDo App na Feira (Google Cloud)

Comandos no **Git Bash** (Windows) ou terminal Linux/macOS, **na pasta do repositório**.
O plano B, sem internet nem nuvem, está em [localstack/manual.md](localstack/manual.md).

> **Regra de ouro:** reiniciar serviço **não apaga dados**. Só `limpar-lista`, `restaurar` e `desativar` mexem nos dados. As três pedem uma palavra de confirmação e fazem backup antes.

## 0. Pré-requisitos (uma vez)

1. **Docker Desktop** aberto, **Git** (inclui o Git Bash) e **Node.js 22**.
2. **Google Cloud CLI** e login: `gcloud auth login`, com uma conta que tenha acesso ao projeto.
3. `infra/gcp/terraform.tfvars`, copiado de `terraform.tfvars.example`, com o `project_id`.
4. Para operar o ambiente **que já existe**: a pasta `.local/gcp/` (chave SSH) e o arquivo `infra/gcp/nat.auto.tfvars`, recebidos do responsável por meio seguro. **Nunca por Git, e-mail ou grupo.** Sem eles, o script geraria outra chave e tentaria religar o NAT.

Confira com `./scripts/pipeline-gcp.sh verificar`.

## 1. Criar do zero (só se o ambiente não existir)

| Passo | Comando | Resultado esperado |
| --- | --- | --- |
| 1 | `./scripts/pipeline-gcp.sh bootstrap` (digite PREPARAR) | `[OK] versionamento ligado` |
| 2 | `./scripts/pipeline-gcp.sh planejar` | `Plan: 26 to add, 0 to change, 0 to destroy` |
| 3 | `./scripts/pipeline-gcp.sh provisionar` (digite CRIAR) | `VM app pronta`, `VM db pronta` |
| 4 | `./scripts/pipeline-gcp.sh implantar` | `[OK] Versão … no ar em https://…` |
| 5 | `./scripts/pipeline-gcp.sh nat desligar` | `Apply complete!` |
| 6 | `./scripts/pipeline-gcp.sh aceite` | `[OK] aceite concluído` |

**Confira o plano antes do passo 3.** Se aparecer algo a destruir que você não esperava, pare.

## 2. Antes de cada apresentação

1. `./scripts/pipeline-gcp.sh status`: tudo `healthy` e saúde `ok`?
2. Abra o endereço no celular, **em 4G**.
3. `./scripts/pipeline-gcp.sh limpar-lista` (digite LIMPAR): lista de demonstração nova.
4. Avise os visitantes: **a lista é compartilhada**. Não digitem dados pessoais.

## 3. Verificar e diagnosticar

| Quero… | Comando |
| --- | --- |
| Estado geral | `./scripts/pipeline-gcp.sh status` |
| Logs da aplicação | `./scripts/pipeline-gcp.sh logs-app` ou `logs-app backend 50` |
| Logs do banco | `./scripts/pipeline-gcp.sh logs-banco 100` |
| Saúde | abrir `<endereço>/health` → `{"status":"ok","api":"ok","banco":"ok"}` |
| Provar o isolamento do banco | `./scripts/pipeline-gcp.sh verificar-isolamento` |

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| "Não foi possível falar com o servidor" | API sem banco | `status`; se preciso, `reiniciar-banco` |
| `/health` com `"banco":"desconectado"` | Banco reiniciando | Espere 1 minuto; a API reconecta sozinha. Depois, `reiniciar-banco` |
| Site não abre | VMs pausadas | `retomar` |
| Só a aplicação falha | Contêiner travado | `reiniciar-app` |
| "sem SSH" ou pedido de login | Sessão do gcloud vencida | `gcloud auth login` |
| Detalhe de erro do SSH | Túnel IAP | veja `.local/gcp/ssh/iap.log` (um erro ao **fechar** o túnel no Windows é normal) |
| `Plan` mostra mudança inesperada | Arquivos da seção 0 ausentes | não aplique; chame o responsável |

## 4. Atualizar e voltar versão

| Quero… | Comando |
| --- | --- |
| Publicar o código atual | `./scripts/pipeline-gcp.sh implantar` |
| Ver versões | `./scripts/pipeline-gcp.sh versoes` |
| Voltar versão | `./scripts/pipeline-gcp.sh implantar <versão>` |

Atualizar **não apaga tarefas**. O rollback volta só a aplicação; para os dados, use a seção 5. Pelo GitHub: aba **Actions > GCP > Run workflow**.

## 5. Backup e recuperação

| Quero… | Comando |
| --- | --- |
| Backup agora (nuvem + `.local/backups/`) | `./scripts/pipeline-gcp.sh backup` |
| Listar | `./scripts/pipeline-gcp.sh backups` |
| **Testar** um backup | `./scripts/pipeline-gcp.sh restaurar-teste [arquivo]` |
| **Voltar** a lista para um backup | `./scripts/pipeline-gcp.sh restaurar <arquivo>` (digite RESTAURAR) |

Limpou a lista sem querer? Em `backups`, pegue o `…-pre-reset.archive.gz` mais recente e use `restaurar`.

## 6. Custos e encerramento

| Situação | Comando | Custo |
| --- | --- | --- |
| Até a feira | nada, deixe ligado | dentro da cota grátis por cerca de 15 dias/mês |
| Tirar do ar por pouco tempo | `pausar` / `retomar` | o IP reservado cobra ≈ US$ 0,01/h |
| **Depois da feira** | `desativar` (digite DESTRUIR) | resta o bucket do estado, poucos KB |
| Encerrar de vez | `gcloud projects delete <projeto>` | nenhum |

`desativar` salva um backup final em `.local/backups/` e só então remove VMs, rede, discos, imagens, segredos e backups da nuvem. **Se o backup falhar, ele para**; nesse caso, salve o que for possível e apague o projeto. No dia seguinte, confira **Faturamento > Relatórios**.

## 7. Ensaio dos alunos (ACE-10)

Cada item feito **pelos alunos**, com data, nome e print:

- [ ] Abrir o endereço em um celular e fazer o fluxo: adicionar, concluir, reabrir, excluir, recarregar
- [ ] `status` e explicar o resultado
- [ ] `logs-app backend 50`
- [ ] `reiniciar-app` e conferir que as tarefas continuam
- [ ] `backup`, `backups` e `restaurar-teste`
- [ ] `limpar-lista` e, em seguida, `restaurar` o `pre-reset`
- [ ] Simular falha: `reiniciar-banco`, observar `/health` e explicar a recuperação
- [ ] Explicar como desativar e o que permanece
