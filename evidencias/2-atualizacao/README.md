# Cenário 2 · Atualização do ambiente

> Alterar parâmetros e executar novamente: pelo menos uma alteração de infraestrutura via Terraform e uma atualização de manutenção via Ansible, sem ajustes manuais no servidor.

## Execução

- **Link:** [46074246440](https://github.com/SoaresPedroBit/todo-app/actions/runs/46074246440) · ✅ sucesso · 5 min 50 s
- **Data:** 27/11/2026, 22:03 UTC · **Commit:** `bacd44f`

## Parâmetros usados (mudanças em negrito)

| Parâmetro | Antes | Nesta execução | Efeito |
| --- | --- | --- | --- |
| acao | (nenhuma) | `provisionar_e_implantar` | |
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

## Manutenção pelo Ansible: pacotes e imagem (27/11, depois do PR #3)

Duas execuções seguidas pelo GitHub, sem nenhum acesso manual às VMs. Uma consulta ao `/health` a cada 5 s, durante as duas, teve uma única falha (502 às 23:41:32 UTC, na troca dos contêineres da aplicação).

| Execução | Parâmetros alterados | Terraform | Ansible `configurar.yml` | Ansible `implantar.yml` |
| --- | --- | --- | --- | --- |
| [46083527513](https://github.com/SoaresPedroBit/todo-app/actions/runs/46083527513) · 23:37 UTC | `extra_packages=htop`, `docker_tag` vazio | NAT do banco criado: **`Plan: 2 to add`**, `Apply complete! 2 added` | `changed=0`: `htop` já vem no Ubuntu; atualizações pendentes listadas (15 na aplicação, 34 no banco) | Versão nova **`58e7363`** construída e implantada: `todo-app` `changed=5`, banco não reiniciado |
| [46084051466](https://github.com/SoaresPedroBit/todo-app/actions/runs/46084051466) · 23:43 UTC | **`extra_packages=curl,git,unzip`**, `docker_tag=58e7363` | `No changes` (NAT já ligado) | **`changed=1` nas duas VMs**: `unzip` (e o que faltava) instalado; na VM do banco, pelo NAT | `changed=0` nas duas VMs |

```text
==> 1. Terraform plan (46083527513)
NAT do banco: true (VM do banco: todo-db)
  # google_compute_router.todo[0] will be created
  # google_compute_router_nat.todo[0] will be created
Plan: 2 to add, 0 to change, 0 to destroy.

TASK [base : Mostrar as atualizações pendentes]
ok: [todo-app] => "15 pacote(s) com atualização pendente no cache do apt (não aplicadas: update_os=false): ..."
ok: [todo-db]  => "34 pacote(s) com atualização pendente no cache do apt (não aplicadas: update_os=false): ..."

==> Construindo e publicando imagens (58e7363)
  [OK] frontend:58e7363
  [OK] backend:58e7363
  [OK] mongo:db-51f5a5f41e (já publicada)
  [OK] Versão 58e7363 no ar em https://34-73-148-18.sslip.io

==> 2. Ansible configurar.yml (46084051466)
TASK [base : Instalar pacotes adicionais solicitados na pipeline]
changed: [todo-db]
changed: [todo-app]
todo-app                   : ok=14   changed=1    unreachable=0    failed=0    skipped=4
todo-db                    : ok=22   changed=1    unreachable=0    failed=0    skipped=5
```

A reexecução com os mesmos parâmetros está no [Cenário 3](../3-reexecucao-sem-alteracoes/). Em seguida, [46084658210](https://github.com/SoaresPedroBit/todo-app/actions/runs/46084658210) (23:50 UTC) rodou sem `extra_packages`: o NAT foi removido (`Plan: 0 to add, 0 to change, 2 to destroy`) e o Ansible ficou com `changed=0` nas duas VMs. O banco voltou a não ter saída para a internet.

`update_os=true` (aplicar as atualizações do SO, `apt dist-upgrade`) não foi executado no ambiente da feira: a VM do banco tem atualização de kernel pendente, que exigiria reiniciá-la. A verificação das atualizações pendentes roda em toda execução.
