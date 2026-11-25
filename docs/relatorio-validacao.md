/r# Relatório de validação · ToDo App (Google Cloud)

Evidências dos critérios de aceite do [escopo](escopo.md), seção 16.
**Data:** 24/11/2026 (horários em UTC). **Endereço:** https://34-73-148-18.sslip.io
**Código:** commit base `4814004` com alterações ainda não commitadas (versões `4814004-local…`).
O relatório do ambiente local está em [localstack/relatorio-validacao.md](localstack/relatorio-validacao.md).

Os registros completos ficam em `.local/evidencias/aceite-gcp-<data>.log`, gerados por `./scripts/pipeline-gcp.sh aceite`.

## Resumo

| Critério | Resultado | Evidência ou pendência |
| --- | --- | --- |
| ACE-01 · Reprodução | ⚠️ parcial | Criado do zero **uma vez** pelo código (26 recursos); plano seguinte *No changes*. Falta destruir e recriar. |
| ACE-02 · Duas VMs | ✅ | `todo-app` e `todo-db`, `e2-micro`; MongoDB só na segunda. |
| ACE-03 · Isolamento | ✅ | 8 verificações, abaixo. |
| ACE-04 · Aplicação pública | ⚠️ quase | Fluxo completo por HTTPS automatizado. Em celular, a equipe informou que funcionou; **faltam os prints** e a confirmação do fluxo completo em 4G. |
| ACE-05 · Persistência | ✅ | Recriação do contêiner, reinício da VM e implantação de versão com outra identificação. |
| ACE-06 · Automação | ⏳ | Plano, criação, implantação, versão identificada e rollback executados **da máquina da equipe**. Workflows ainda **não executados no GitHub**. |
| ACE-07 · Recuperação | ✅ | Backup no Cloud Storage e restauração isolada. Agendamento de 6 h instalado e o mesmo comando executado à mão; **conferir as execuções automáticas nos próximos dias**. |
| ACE-08 · Operação | ⚠️ quase | Saúde, logs, reinício, pausa e retomada testados; credenciais ausentes. **`desativar` ainda não executado na GCP.** |
| ACE-09 · Custos | ✅ | [arquitetura.md, seção 8](arquitetura.md#8-custos-ace-09), com preços do catálogo oficial em 24/11/2026. Comparar com o faturamento real após o evento. |
| ACE-10 · Transferência | ⏳ | [Manual](manual-alunos.md) pronto; falta o ensaio conduzido pelos alunos (seção 7 do manual). |

## Execuções do aceite

| Início | Resultado | Observação |
| --- | --- | --- |
| 21:29 | Aprovado | Restauração de teste levou 100 s: primeiro sinal do problema abaixo |
| 22:09 | **Reprovado** | A VM do banco parou de responder durante a restauração de teste |
| 22:35 | Aprovado | Depois da correção; restauração de teste em 16 s |

### Falha encontrada e corrigida

**Sintoma:** na VM do banco (1 GB), uso de CPU acima de 80%, centenas de MB/min de leitura e escrita no disco de sistema e SSH sem resposta. O `/health` da aplicação continuou respondendo.

**Causa:** o healthcheck abria um `mongosh` (mais de 100 MB) a cada 15 s, e o contêiner da restauração de teste herdava o mesmo healthcheck. Com dois bancos e vários `mongosh`, a VM entrou em troca intensa de memória.

**Correção:** healthcheck a cada 60 s (frequente só na subida) e desligado no contêiner de teste, que passou a ser verificado pela porta. Em repouso, a CPU da VM do banco caiu de cerca de 40% para 1% a 2%.

**Recuperação:** a VM foi desligada e ligada; nenhuma tarefa foi perdida nesse reinício.

## Detalhes

### ACE-03 · Isolamento

```text
  [OK] VM do banco sem IP público (privado: 10.10.2.10)
  [OK] 27017 fechada na internet (34.73.148.18)
  [OK] 22 fechada na internet (34.73.148.18)
  [OK] banco inacessível desta máquina (10.10.2.10)
  [OK] 443 responde (o teste de porta funciona)
  [OK] VM da aplicação alcança o banco pela rede privada
  [OK] MongoDB escuta apenas em 10.10.2.10:27017
  [OK] API conectada ao banco
```

Regras de entrada da VPC: `todo-web` (80/443 de qualquer origem), `todo-mongo` (27017 só da conta de serviço da aplicação) e `todo-ssh-iap` (22 só de 35.235.240.0/20).

### ACE-04 · HTTPS

Certificado Let's Encrypt, válido até 22/02/2027, verificado sem exceções. HTTP responde 308 para HTTPS. Cadastrar, listar, concluir, reabrir, excluir e recusar tarefa sem texto: todos `[OK]`.

### ACE-05 e ACE-06 · Versões

| Passo | Resultado |
| --- | --- |
| `4814004-local11241820` → `…1851` | Contêineres da aplicação trocados; tarefa concluída preservada; **MongoDB não reiniciou** |
| Versão inexistente | Recusada antes de qualquer alteração |
| Rollback para `…1820` | Aplicado sem reconstruir; tarefa preservada |

As duas versões tinham o mesmo código-fonte da aplicação: o teste cobre o processo de troca, não uma mudança funcional.

### ACE-07 · Backup e restauração

```text
[22:40:39] Backup concluído: todo-20261124T224037Z-aceite.archive.gz
[22:40:49] Subindo MongoDB isolado (--network none, sem portas, dados temporários)
Tarefas no backup restaurado: 2
Tarefas na produção agora:    2 (não alterada)
[22:41:05] Restauração de teste OK; contêiner temporário removido
```

A restauração **na produção** (`restaurar`) não foi executada na GCP; o mesmo código foi testado no ambiente local.

### ACE-08 · Pausa e retomada

`pausar` fez backup, desligou as VMs e tirou o site do ar; `retomar` o devolveu em cerca de 80 s, com o mesmo IP e dados idênticos. As senhas reais, lidas do Secret Manager, não aparecem no código, nos logs das VMs nem nas evidências.

### Validação de código

`terraform fmt` e `validate` (`infra/gcp` e `infra/gcp-ci`), shellcheck e actionlint sem erros. Os scripts de operação, compartilhados com o ambiente local, foram reimplantados no LocalStack: 24 de 24 verificações e dados idênticos.

## Pendências

1. Prints do fluxo em celular (ACE-04).
2. Execução dos workflows no GitHub (ACE-06).
3. Destruir e recriar, incluindo `desativar` (ACE-01, ACE-08). Muda o IP: fazer em projeto temporário ou após a feira.
4. Ensaio dos alunos (ACE-10).
5. Conferir backups automáticos e faturamento nos próximos dias.
6. Registrar os responsáveis pelos acessos (escopo, seção 15): conta da nuvem, repositório e operação na feira.
