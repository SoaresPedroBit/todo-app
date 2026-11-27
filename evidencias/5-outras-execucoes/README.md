# Outras execuções no GitHub Actions

| Workflow | Resultado | Execução |
| --- | --- | --- |
| CI (validação: `terraform fmt/validate`, shellcheck, `ansible-playbook --syntax-check`, testes) | Aprovado | [45710600792](https://github.com/SoaresPedroBit/todo-app/actions/runs/45710600792) |
| Ciclo local (LocalStack, plano B) | Aprovado | [45710600829](https://github.com/SoaresPedroBit/todo-app/actions/runs/45710600829) |
| GCP · planejar | Aprovado na 2ª tentativa (*No changes*) | [45604931988](https://github.com/SoaresPedroBit/todo-app/actions/runs/45604931988) |
| GCP · rollback | Aprovado | [45704028562](https://github.com/SoaresPedroBit/todo-app/actions/runs/45704028562) |
| GCP · implantar `d058a58` | Aprovado | [45704257404](https://github.com/SoaresPedroBit/todo-app/actions/runs/45704257404) |
| GCP · aceite | Aprovado na 2ª tentativa | [45704640419](https://github.com/SoaresPedroBit/todo-app/actions/runs/45704640419) |

A 1ª tentativa de `planejar` falhou por falta de permissão para ler metadados de buckets (corrigido em `4572a82`). Um disparo de rollback falhou por queda de internet e foi refeito.

## Ciclo completo em projeto temporário (25/11/2026, máquina da equipe)

| Etapa | Resultado |
| --- | --- |
| `provisionar` | 26 recursos criados; Ansible com `failed=0` nas duas VMs |
| `preparar`, segunda vez | `changed=0`: idempotente |
| `implantar` | Aplicação no ar com HTTPS |
| `nat desligar` e `preparar`, terceira vez | 2 recursos removidos; `changed=0` sem internet no banco |
| `aceite` | Aprovado |
| `desativar` | Backup final copiado; 24 recursos destruídos |
