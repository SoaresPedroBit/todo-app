# Evidências · PM-04

Índice das evidências pedidas no enunciado do PM-04 (seção 5, "Testes obrigatórios na apresentação").
Cada pasta corresponde a um cenário e traz os parâmetros usados, o link da execução no GitHub Actions e os trechos de log que comprovam o resultado.

**Repositório:** https://github.com/SoaresPedroBit/todo-app · **Aplicação:** https://34-73-148-18.sslip.io
**Pipeline:** [`.github/workflows/gcp.yml`](../.github/workflows/gcp.yml) (aba *Actions* → *GCP* → *Run workflow*)

| Cenário do PM-04 | Pasta | Execução no GitHub Actions | Situação |
| --- | --- | --- | --- |
| 1 · Criação inicial | [1-criacao-inicial](1-criacao-inicial/) | Mesma rotina, em projeto temporário (25/11): 26 recursos | ✅ validado · ⏳ pelo GitHub após a feira |
| 2 · Atualização do ambiente | [2-atualizacao](2-atualizacao/) | [46074246440](https://github.com/SoaresPedroBit/todo-app/actions/runs/46074246440) | ✅ `e2-micro → e2-small` sem recriar; imagem `bacd44f` |
| 3 · Reexecução sem alterações | [3-reexecucao-sem-alteracoes](3-reexecucao-sem-alteracoes/) | [46077818369](https://github.com/SoaresPedroBit/todo-app/actions/runs/46077818369) | ✅ `No changes`; Ansible `changed=0` |
| Validação da demanda | [4-validacao-demanda](4-validacao-demanda/) | [aceite 45704640419](https://github.com/SoaresPedroBit/todo-app/actions/runs/45704640419) | ✅ |
| Demais execuções (CI, LocalStack, rollback…) | [5-outras-execucoes](5-outras-execucoes/) | várias | ✅ |

## Onde ver os logs completos

Toda execução da pipeline anexa, ao final, o artefato **`evidencias-gcp-<acao>-<environment>`** com o plano do Terraform (`plano.txt`) e os registros do aceite.
Para baixar: abra o link da execução → seção *Artifacts* no fim da página.

## O que observar em cada log

| Ferramenta | Onde, no log da execução | O que comprova |
| --- | --- | --- |
| Terraform | Etapa **1. Terraform plan**, última linha | `Plan: N to add, M to change, 0 to destroy` (cenários 1 e 2) ou `No changes` (cenário 3) |
| Terraform | Etapa **2. Terraform apply + Ansible**, `Apply complete!` | Recursos criados/alterados sem recriação (`0 destroyed` no cenário 2) |
| Ansible | Etapas 2 e 3, bloco `PLAY RECAP` | `failed=0` nas duas VMs; `changed=0` no cenário 3 (idempotência) |
| Aplicação | Etapa **3**, fim | `Versão <tag> no ar em https://…` e teste de fumaça aprovado |
