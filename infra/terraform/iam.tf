# ===========================================================================
# Perfis das instâncias (privilégio mínimo). Cada VM só acessa o que usa.
# ===========================================================================
data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "todo-app-vm"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role" "db" {
  name               = "todo-db-vm"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_instance_profile" "app" {
  name = "todo-app-vm"
  role = aws_iam_role.app.name
}

resource "aws_iam_instance_profile" "db" {
  name = "todo-db-vm"
  role = aws_iam_role.db.name
}

# Administração sem SSH (Session Manager) — usada pelas duas VMs
data "aws_iam_policy_document" "ssm" {
  statement {
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

# API: lê somente a senha do próprio usuário no banco
data "aws_iam_policy_document" "app" {
  source_policy_documents = [data.aws_iam_policy_document.ssm.json]
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [data.aws_secretsmanager_secret.mongo_app.arn]
  }
}

# Banco: as duas senhas e o bucket de backups
data "aws_iam_policy_document" "db" {
  source_policy_documents = [data.aws_iam_policy_document.ssm.json]
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      data.aws_secretsmanager_secret.mongo_root.arn,
      data.aws_secretsmanager_secret.mongo_app.arn,
    ]
  }
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backups.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.backups.arn}/mongo/*"]
  }
}

resource "aws_iam_role_policy" "app" {
  name   = "todo-app-vm"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}

resource "aws_iam_role_policy" "db" {
  name   = "todo-db-vm"
  role   = aws_iam_role.db.id
  policy = data.aws_iam_policy_document.db.json
}

# Segredos: criados pelo bootstrap (fora do Terraform, para que as senhas
# não fiquem gravadas no estado). Aqui só são referenciados.
data "aws_secretsmanager_secret" "mongo_root" {
  name = var.mongo_root_secret
}

data "aws_secretsmanager_secret" "mongo_app" {
  name = var.mongo_app_secret
}
