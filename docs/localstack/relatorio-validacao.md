# Relatório de validação · ToDo App (LocalStack)

> **Ambiente alternativo.** A entrega principal roda na Google Cloud: [arquitetura](../arquitetura.md), [manual](../manual-alunos.md), [relatório](../relatorio-validacao.md). Este documento descreve a versão local, sem custo, mantida como plano B.

Evidências dos critérios de aceite do [escopo](../escopo.md), seção 16.
**Ambiente:** Windows 11 + Docker Desktop 28.1, LocalStack Community 4.14.0, Terraform 1.9.8 (em contêiner).
**Data:** 18/11/2026. **Versão do código:** commit base `4814004` com as alterações deste trabalho.

Os relatórios completos ficam em `.local/evidencias/aceite-<data>.log`, gerados por `./scripts/pipeline.sh aceite`. No GitHub, cada execução do workflow *Infraestrutura e entrega (LocalStack)* anexa o seu relatório.

## Resumo

| Critério | Resultado | Evidência |
| --- | --- | --- |
| ACE-01 · Reprodução | ✅ | Ambiente criado do zero 3 vezes com `ciclo-completo` (41 recursos), destruído 2 vezes com `desativar` (41 destruídos). Plano seguinte: *No changes*. |
| ACE-02 · Duas VMs | ✅ | Inventário: `todo-app` (10.10.1.10, Elastic IP) e `todo-db` (10.10.2.10, sem IP público). MongoDB só na VM do banco. |
| ACE-03 · Isolamento | ✅ | 7 verificações: sem IP público, nenhuma porta publicada, SG com entrada única, 27017 fechada de fora **e** para outro host da VPC, aberta só para a aplicação, Mongo escutando só no IP privado. |
| ACE-04 · Aplicação pública | ⚠️ parcial | Fluxo completo por **HTTPS** validado (`https://localhost`, CA verificada, HTTP → 308). **Não há URL na internet** (decisão LocalStack); acesso por outro dispositivo só pela rede local, procedimento no manual, seção 1 (**não testado em outro aparelho**). |
| ACE-05 · Persistência | ✅ | Tarefa concluída preservada após recriar o contêiner do banco, reiniciar a VM do banco e atualizar a aplicação. Também após o LocalStack perder todo o estado (teste manual, abaixo). |
| ACE-06 · Automação | ✅ local / ⏳ GitHub | Rotinas executadas localmente: plan/apply/destroy, implantar com versão, rollback. Os workflows `ci.yml` e `localstack.yml` estão prontos, mas **ainda não rodaram no GitHub** (sem push). |
| ACE-07 · Recuperação | ✅ | Backup agendado (cron 6 h) + backup sob demanda no S3 e restauração em MongoDB **sem rede**, com produção inalterada. Restauração real testada. |
| ACE-08 · Operação | ✅ | `status`, `/health`, `logs-*`, `reiniciar-*`, `desativar`. Senhas reais **não encontradas** no código versionado, nos logs das VMs nem nas evidências. |
| ACE-09 · Custos | ⚠️ parcial | [arquitetura.md §8](arquitetura.md#8-custos-ace-09): R$ 0 nesta solução, mais uma referência para a AWS real (preços aproximados, a conferir). |
| ACE-10 · Transferência | ⏳ | [Manual dos alunos](manual.md) pronto. **Depende da demonstração conduzida pelos alunos.** |

## Detalhes

### ACE-01 · Reprodução

Sequência executada em 18/11/2026: `ciclo-completo` → `desativar` → `ciclo-completo` → `desativar` → `ciclo-completo`.

```text
Apply complete! Resources: 41 added, 0 changed, 0 destroyed.
Destroy complete! Resources: 41 destroyed.
Apply complete! Resources: 41 added, 0 changed, 0 destroyed.
...
No changes. Your infrastructure matches the configuration.
```

Problema encontrado e corrigido nesse teste: com o banco **vazio**, a imagem do MongoDB sobe um processo temporário para rodar o `init-mongo.js`. O healthcheck passava nele e o deploy tentava criar o usuário no momento do reinício (`ECONNREFUSED`). Agora o `ops.sh` espera o fim da inicialização (`aguardar_mongo`), e a recriação do zero seguinte passou.

Segundo problema encontrado: o LocalStack descarta a `description` de regras de SG que referenciam outro SG, o que deixava 1 alteração pendente após cada criação. A descrição foi removida dessa regra e a nova recriação do zero mostrou *No changes* já no primeiro plano.

Pré-requisitos e parâmetros: [manual, seção 0](manual.md#0-pré-requisitos-uma-vez). Parâmetros opcionais: `SITE_ADDRESS`, `HTTP_PORT`, `HTTPS_PORT` e as variáveis em `infra/terraform/variables.tf`.

### ACE-02 · Inventário

```text
|  todo-app|  i-1ba8736fa29011fdb  |  t3.small |  10.10.1.10 |  127.122.165.159  |
|  todo-db |  i-fe5dff3369a033817  |  t3.small |  10.10.2.10 |  -                |
  [OK] MongoDB roda sozinho na VM do banco
  [OK] nenhum MongoDB na VM da aplicação
```

VPC 10.10.0.0/16; sub-redes pública 10.10.1.0/24 e privada 10.10.2.0/24; NAT Gateway; EBS gp3 de 10 GB anexado ao `todo-db`; S3 `todo-app-backups`. Os IDs mudam a cada recriação.

### ACE-03 · Isolamento

```text
  [OK] sem IP público (privado: 10.10.2.10)
  [OK] VM do banco não publica nenhuma porta
|  27017|  27017 |  tcp |  - |  sg-48ccf5253f3153136   |      <- única entrada do todo-db-sg
  [OK] única entrada: 27017 a partir de sg-48ccf5253f3153136 (todo-app-sg)
  [OK] 27017 inacessível a partir desta máquina
  [OK] bloqueado pelo firewall da VM do banco (equivalente ao SG)     <- host 10.10.1.99 na VPC
  [OK] 10.10.1.10 -> 10.10.2.10:27017 conecta
  [OK] API conectada ao banco: {"status":"ok","api":"ok","banco":"ok"}
  [OK] MongoDB escuta apenas em 10.10.2.10:27017
```

Também verificado: o usuário `todo_app` **não** consegue ler `admin.system.users` (`not authorized`).

### ACE-04 · Aplicação pelo HTTPS

```text
Teste de fumaça em https://localhost
  [OK] GET / entrega a interface
  [OK] GET /health: API e banco ok
  [OK] POST /todos: tarefa criada
  [OK] GET /todos: tarefa listada
  [OK] PATCH /todos/:id: concluída
  [OK] PATCH /todos/:id: reaberta
  [OK] DELETE /todos/:id: excluída
  [OK] POST /todos sem texto: 400
  HTTP -> 308 redireciona para https://localhost/
```

O certificado é validado contra a CA exportada (`--cacert`), sem `--insecure`. **Pendente:** abrir em um celular ou notebook pela rede local e recarregar a página.

### ACE-05 · Persistência

```text
  [OK] tarefa 'persistencia-…' criada e concluída
  [OK] preservada após RECRIAR o contêiner do banco (volume mantido)
  [OK] preservada após REINICIAR a VM do banco
  [OK] preservada (com estado concluída) após ATUALIZAR a aplicação
```

Teste adicional (manual, 18/11): `parar-localstack` → `subir-localstack` (S3, EC2 e segredos **vazios**) → `provisionar` → `implantar`. As 4 tarefas, incluindo uma criada por "visitante", voltaram intactas.

### ACE-06 · Automação, versões e rollback

```text
==> Versões publicadas no registro
4814004-local11172118 4814004-local11172112
### rollback para 4814004-local11172112
Rollback da aplicação: o banco permanece na imagem atual (os dados não voltam no tempo)
  [OK] Versão 4814004-local11172112 no ar em https://localhost
```

A atualização da aplicação **não** reinicia o MongoDB, porque a tag `db-<hash>` só muda quando a pasta `banco-de-dados/` muda. Uma versão inexistente é recusada antes de qualquer alteração.

### ACE-07 · Backup e restauração

```text
  agendamento: 0 */6 * * * . /opt/todo/instancia.env && /opt/todo/ops.sh backup agendado ...
[22:31:21] Backup concluído: todo-20261118T223120Z-aceite.archive.gz (4.0K)
[22:31:23] Subindo MongoDB isolado (--network none, sem portas, dados temporários)
Tarefas no backup restaurado: 3
Tarefas na produção agora:    3 (não alterada)
[22:31:28] Restauração de teste OK; contêiner temporário removido
```

Restauração na produção (manual): a lista foi limpa com `limpar-lista` (4 → 3 tarefas) e restaurada com `restaurar <…-pre-reset…>`. A tarefa `visitante-1` voltou, e um backup `pre-restore` foi gerado antes. Sem a palavra de confirmação, as rotinas são recusadas.

### ACE-08 · Operação e credenciais

```text
{"status":"ok","api":"ok","banco":"ok"}
backend-1  | ... Conexão com o MongoDB perdida; o driver tentará reconectar
backend-1  | ... Reconectado ao MongoDB
  [OK] nenhuma senha no código, nos logs das VMs ou nas evidências
```

As reconexões no log são esperadas: são os reinícios provocados pelo próprio teste de persistência.

### Validação de código

- Frontend: 3 testes (listar por caminho relativo; adicionar, concluir e excluir; aviso de API indisponível) passando.
- Shellcheck sem avisos; `terraform fmt -check` e `terraform validate` ok.
- Compose local: fluxo completo, persistência após recriar o contêiner e portas 27017/5000 fechadas.
