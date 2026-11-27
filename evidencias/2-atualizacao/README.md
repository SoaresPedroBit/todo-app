# Cenário 2 · Atualização do ambiente

> Alterar parâmetros e executar novamente: pelo menos uma alteração de infraestrutura via Terraform e uma atualização de manutenção via Ansible, sem ajustes manuais no servidor.

## Execução

- **Link:** [46074246440](https://github.com/SoaresPedroBit/todo-app/actions/runs/46074246440) · ✅ sucesso · 5 min 50 s
- **Data:** 27/11/2026, 22:03 UTC · **Commit:** `bacd44f`

## Parâmetros usados (mudanças em negrito)

| Parâmetro | Antes | Nesta execução | Efeito |
| --- | --- | --- | --- |
| acao | — | `provisionar_e_implantar` | |
| environment | `dev` | `dev` | |
| instance_name | `todo-pm04` | `todo-pm04` | |
| instance_type | `e2-micro` | **`e2-small`** | Alteração de infraestrutura (Terraform) |
| docker_tag | versão anterior no ar | _(vazio = commit)_ → **`bacd44f`** | Atualização da imagem Docker (Ansible) |
| update_os / extra_packages | `false` / vazio | `false` / vazio | |

## Resultado

| Etapa | Obtido |
| --- | --- |
| Terraform plan | `machine_type: "e2-micro" -> "e2-small"` nas duas VMs; **`Plan: 0 to add, 2 to change, 0 to destroy`** |
| Terraform apply | **`Resources: 0 added, 2 changed, 0 destroyed`**: VMs alteradas no lugar (`allow_stopping_for_update`), mesmo IP e mesmo disco de dados |
| Ansible `configurar.yml` | `failed=0` nas duas VMs (`changed=0`: Docker e pacotes já estavam prontos) |
| Ansible `implantar.yml` | `todo-app`: `changed=3` (imagens `bacd44f` baixadas, contêineres trocados, versão registrada, imagens antigas apagadas); `todo-db`: `changed=0` (banco não reiniciado) |
| Verificação pública | `[OK] Versão bacd44f no ar em https://34-73-148-18.sslip.io` |

## Trechos do log

```text
==> 1. Terraform plan
      ~ machine_type               = "e2-micro" -> "e2-small"
      ~ machine_type               = "e2-micro" -> "e2-small"
Plan: 0 to add, 2 to change, 0 to destroy.

==> 2. Terraform apply + Ansible (configurar as VMs)
google_compute_instance.vm["db"]: Modifications complete after 1m29s
google_compute_instance.vm["app"]: Modifications complete after 1m40s
Apply complete! Resources: 0 added, 2 changed, 0 destroyed.

PLAY RECAP *********************************************************************
todo-app                   : ok=10   changed=0    unreachable=0    failed=0    skipped=4
todo-db                    : ok=18   changed=0    unreachable=0    failed=0    skipped=5

==> 3. Ansible (subir os contêineres)
TASK [aplicacao : Subir a aplicação] *******************************************
changed: [todo-app]

PLAY RECAP *********************************************************************
todo-app                   : ok=15   changed=3    unreachable=0    failed=0    skipped=0
todo-db                    : ok=20   changed=0    unreachable=0    failed=0    skipped=2

  [OK] Versão bacd44f no ar em https://34-73-148-18.sslip.io
```

## Retorno ao tipo gratuito

Logo depois, [46074985970](https://github.com/SoaresPedroBit/todo-app/actions/runs/46074985970) (22:10 UTC) voltou as VMs para `e2-micro` (`e2-small` é cobrada): Terraform `0 added, 2 changed, 0 destroyed`; Ansible com `changed=0 failed=0` nas duas VMs.

## Outras manutenções pelo Ansible

Os parâmetros `update_os=true` (atualização do SO) e `extra_packages` (por exemplo `curl,git,unzip`) acionam as tarefas "Atualizar pacotes do sistema operacional" e "Instalar pacotes adicionais" em [`roles/base`](../../infra/ansible/roles/base/tasks/main.yml) e ligam automaticamente o Cloud NAT do banco para que ele alcance os repositórios.
