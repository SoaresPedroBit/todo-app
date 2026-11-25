# Relatório de validação · ToDo App (Google Cloud)

Evidências dos critérios de aceite do [escopo](escopo.md), seção 16.
**Datas:** 24 e 25/11/2026 (horários em UTC). **Endereço:** https://34-73-148-18.sslip.io
**Código:** [SoaresPedroBit/todo-app](https://github.com/SoaresPedroBit/todo-app), ramo `main`. Os testes de 24/11 usaram versões `4814004-local…`, anteriores ao commit.
O relatório do ambiente local está em [localstack/relatorio-validacao.md](localstack/relatorio-validacao.md).

Os registros completos ficam em `.local/evidencias/` (não versionado) e, nas execuções do GitHub, como artefato na aba Actions.

## Resumo

| Critério | Resultado | Evidência ou pendência |
| --- | --- | --- |
| ACE-01 · Reprodução | ✅ | Criado do zero pelo código **duas vezes**, em projetos diferentes (26 recursos cada); pré-requisitos e parâmetros no [manual](manual-alunos.md). |
| ACE-02 · Duas VMs | ✅ | `todo-app` e `todo-db`, `e2-micro`; MongoDB só na segunda. |
| ACE-03 · Isolamento | ✅ | 8 verificações, abaixo. |
| ACE-04 · Aplicação pública | ⚠️ quase | Fluxo completo por HTTPS automatizado. Em celular, a equipe informou que funcionou; **faltam os prints** e a confirmação do fluxo completo em 4G. |
| ACE-05 · Persistência | ✅ | Recriação do contêiner, reinício da VM e implantação de versão com outra identificação. |
| ACE-06 · Automação | ✅ | No GitHub: validação, ciclo local, plano, implantação (versão = commit), rollback e aceite. Criação e desativação na GCP executadas pelo pipeline, da máquina da equipe. |
| ACE-07 · Recuperação | ✅ | Backups automáticos de 25/11 às 00, 06, 12 e 18 h, todos no horário; restauração isolada e restauração real testadas. |
| ACE-08 · Operação | ✅ | Saúde, logs, reinícios, pausa, retomada e `desativar` executados; credenciais ausentes do código e dos registros. |
| ACE-09 · Custos | ✅ | [arquitetura.md, seção 9](arquitetura.md#9-custos-ace-09), com preços do catálogo oficial em 24/11/2026. Comparar com o faturamento real após o evento. |
| ACE-10 · Transferência | ⏳ | [Manual](manual-alunos.md) pronto; falta o ensaio conduzido pelos alunos (seção 7 do manual). |

## Execuções do aceite

| Início | Onde | Resultado | Observação |
| --- | --- | --- | --- |
| 24/11 21:29 | Máquina da equipe | Aprovado | Restauração de teste levou 100 s: primeiro sinal do problema abaixo |
| 24/11 22:09 | Máquina da equipe | **Reprovado** | A VM do banco parou de responder durante a restauração de teste |
| 24/11 22:35 | Máquina da equipe | Aprovado | Depois da correção 1; restauração de teste em 16 s |
| 25/11 21:18 | GitHub Actions | **Reprovado** | Falha 2, abaixo |
| 25/11 21:28 | GitHub Actions | Aprovado | Depois da correção 2; restauração de teste em cerca de 60 s |
| 25/11 22:10 | Projeto temporário | Aprovado | Ambiente criado do zero, configurado com Ansible |

### Falha 1: memória da VM do banco (corrigida)

**Sintoma:** na VM do banco (1 GB), uso de CPU acima de 80%, centenas de MB/min de leitura e escrita no disco de sistema e SSH sem resposta. O `/health` da aplicação continuou respondendo.

**Causa:** o healthcheck abria um `mongosh` (mais de 100 MB) a cada 15 s, e o contêiner da restauração de teste herdava o mesmo healthcheck. Com dois bancos e vários `mongosh`, a VM entrou em troca intensa de memória.

**Correção:** healthcheck a cada 60 s (frequente só na subida) e desligado no contêiner de teste, que passou a ser verificado pela porta. Em repouso, a CPU da VM do banco caiu de cerca de 40% para 1% a 2%.

**Recuperação:** a VM foi desligada e ligada; nenhuma tarefa foi perdida nesse reinício.

### Falha 2: implantação logo após queda do banco (corrigida)

**Sintoma:** `container todo-app-backend-1 is unhealthy` ao reimplantar logo após reiniciar a VM do banco.

**Causa:** a API já respondia, mas o Docker ainda guardava o resultado da checagem anterior, e o `up --wait` falhou na hora.

**Correção:** o `ops.sh` espera até um minuto a checagem se recuperar antes de implantar.

## Execuções no GitHub

| Workflow | Resultado | Execução |
| --- | --- | --- |
| CI (validação, integração) | Aprovado | [45710600792](https://github.com/SoaresPedroBit/todo-app/actions/runs/45710600792) |
| Ciclo local (LocalStack) | Aprovado | [45710600829](https://github.com/SoaresPedroBit/todo-app/actions/runs/45710600829) |
| GCP · planejar | Aprovado na 2ª tentativa (*No changes*) | [45604931988](https://github.com/SoaresPedroBit/todo-app/actions/runs/45604931988) |
| GCP · rollback | Aprovado | [45704028562](https://github.com/SoaresPedroBit/todo-app/actions/runs/45704028562) |
| GCP · implantar `d058a58` | Aprovado | [45704257404](https://github.com/SoaresPedroBit/todo-app/actions/runs/45704257404) |
| GCP · aceite | Aprovado na 2ª tentativa | [45704640419](https://github.com/SoaresPedroBit/todo-app/actions/runs/45704640419) |

A 1ª tentativa de `planejar` falhou por falta de permissão para ler metadados de buckets. Um disparo de rollback falhou por queda de internet e foi refeito.

## Ciclo completo em projeto temporário (25/11, 21:50 a 22:21)

Projeto criado só para o teste, sem tocar no ambiente da feira.

| Etapa | Resultado |
| --- | --- |
| `provisionar` | 26 recursos criados; Ansible com `failed=0` nas duas VMs |
| `preparar`, segunda vez | `changed=0`: idempotente |
| `implantar` | Aplicação no ar com HTTPS |
| `nat desligar` e `preparar`, terceira vez | 2 recursos removidos; `changed=0` sem internet no banco |
| `limpar-lista` | 4 tarefas → 3; a tarefa de visitante saiu |
| `restaurar` (na produção desse ambiente) | 3 → 4; a tarefa de visitante voltou |
| `limpar-lista` sem a palavra de confirmação | Recusado |
| `reiniciar-banco`, `reiniciar-app`, `status` | Serviços saudáveis |
| `aceite` | Aprovado |
| `desativar` | Backup final copiado; 24 recursos destruídos (os 26 menos os 2 do NAT) |

**Inventário após `desativar`:** 0 VMs, discos, IPs, roteadores, regras, segredos, repositórios e contas de serviço. Restou só o bucket do estado, removido com a exclusão do projeto.

No ambiente da feira, `preparar --check` mostrou `changed=0`: o Ansible descreve exatamente o que está em execução, sem tê-lo alterado.

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

A restauração real (`restaurar`) foi executada no projeto temporário (acima), não no ambiente da feira.

### ACE-08 · Pausa e retomada

`pausar` fez backup, desligou as VMs e tirou o site do ar; `retomar` o devolveu em cerca de 80 s, com o mesmo IP e dados idênticos. As senhas reais, lidas do Secret Manager, não aparecem no código, nos logs das VMs nem nas evidências.

### Validação de código

`terraform fmt` e `validate` (`infra/gcp` e `infra/gcp-ci`), shellcheck e `ansible-playbook --syntax-check` sem erros, no CI; actionlint sem erros, localmente. Os scripts de operação, compartilhados com o ambiente local, foram reimplantados no LocalStack: 24 de 24 verificações e dados idênticos.

## Pendências

1. Prints do fluxo completo em celular, em 4G (ACE-04).
2. Ensaio conduzido pelos alunos (ACE-10).
3. Dados da organização e responsáveis pelos acessos ([arquitetura.md, seção 8](arquitetura.md#8-limitações-e-premissas)).
4. Conferir o faturamento real e fazer o encerramento depois da feira.
5. Sem teste de carga; a margem de memória das VMs é pequena.
