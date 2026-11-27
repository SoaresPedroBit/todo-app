# Cenário 3 · Reexecução sem alterações

> Executar com os mesmos parâmetros e demonstrar ausência de alterações desnecessárias no Terraform e comportamento idempotente do Ansible.

## Execução

- **Link:** [46077818369](https://github.com/SoaresPedroBit/todo-app/actions/runs/46077818369) · ✅ sucesso · 2 min 24 s
- **Data:** 27/11/2026, 22:37 UTC · **Versão no ar:** `025ec50`

## Parâmetros usados

Os mesmos do ambiente em execução, com a versão das imagens fixada explicitamente (recomendação do PM-04 de usar tags reproduzíveis):

| Parâmetro | Valor |
| --- | --- |
| acao | `provisionar_e_implantar` |
| environment | `dev` |
| instance_name | `todo-pm04` |
| instance_type | `e2-micro` |
| docker_tag | `025ec50` (a versão já no ar) |
| update_os | `false` |
| extra_packages | _(vazio)_ |

## Resultado

| Etapa | Obtido |
| --- | --- |
| Terraform plan | **`No changes. Your infrastructure matches the configuration.`** |
| Terraform apply | `Resources: 0 added, 0 changed, 0 destroyed` |
| Imagens | As três já estavam no registro (`já publicada`): nada reconstruído |
| Ansible `configurar.yml` | **`changed=0 failed=0`** nas duas VMs |
| Ansible `implantar.yml` | **`changed=0 failed=0`** nas duas VMs: nenhum contêiner recriado |
| Verificação pública | `[OK] Versão 025ec50 no ar em https://34-73-148-18.sslip.io` |

## Trechos do log

```text
==> 1. Terraform plan
No changes. Your infrastructure matches the configuration.

==> 2. Terraform apply + Ansible (configurar as VMs)
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

PLAY RECAP *********************************************************************
todo-app                   : ok=10   changed=0    unreachable=0    failed=0    skipped=4
todo-db                    : ok=18   changed=0    unreachable=0    failed=0    skipped=5

==> 3. Ansible (subir os contêineres)
  [OK] frontend:025ec50 (já publicada)
  [OK] backend:025ec50 (já publicada)
  [OK] mongo:db-51f5a5f41e (já publicada)

PLAY RECAP *********************************************************************
todo-app                   : ok=13   changed=0    unreachable=0    failed=0    skipped=2
todo-db                    : ok=20   changed=0    unreachable=0    failed=0    skipped=2

  [OK] Versão 025ec50 no ar em https://34-73-148-18.sslip.io
```

## Por que fixar `docker_tag`

Antes do PR #3, com `docker_tag` vazio, a versão era o commit atual da `main`. Uma execução anterior ([46077399897](https://github.com/SoaresPedroBit/todo-app/actions/runs/46077399897)) começou logo depois de um commit só de documentação (`025ec50`): o Terraform já mostrou `No changes`, mas o Ansible implantou corretamente a nova versão (`changed=3` na VM da aplicação). Isso é uma atualização legítima, não falta de idempotência. Com a tag fixa, a mesma entrada produz sempre o mesmo ambiente.

Desde o PR #3, a versão automática é o último commit que alterou `frontend/` ou `backend/`: um commit só de documentação não gera mais versão nova.

## Validações anteriores

- Projeto temporário (25/11/2026): segunda e terceira execuções do `preparar` com `changed=0`.
- [46074985970](https://github.com/SoaresPedroBit/todo-app/actions/runs/46074985970) (27/11): ao voltar para `e2-micro`, os dois playbooks com `changed=0`.
