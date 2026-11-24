# ===========================================================================
# Backups do MongoDB (S3)
# ===========================================================================
resource "aws_s3_bucket" "backups" {
  bucket        = var.backup_bucket_name
  force_destroy = true # o pipeline de desativação faz backup final e exporta antes
  tags          = { Name = "todo-backups" }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    id     = "retencao"
    status = "Enabled"
    filter {
      prefix = "mongo/"
    }
    expiration {
      days = var.backup_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# ===========================================================================
# Volume EBS de dados do MongoDB — separado do disco de sistema
# ===========================================================================
resource "aws_ebs_volume" "mongo_data" {
  availability_zone = var.availability_zone
  size              = var.db_volume_size_gb
  type              = "gp3"
  encrypted         = true
  tags              = { Name = "todo-mongo-data" }
}

resource "aws_volume_attachment" "mongo_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.mongo_data.id
  instance_id = aws_instance.db.id
}

# Materialização local do EBS: volume Docker que sobrevive à recriação do
# contêiner do banco e da própria VM.
#
# Propositalmente SEM vínculo com o ID do EBS: o LocalStack Community perde
# tudo ao reiniciar e recria o EBS com outro ID; se o volume dependesse desse
# ID, o Terraform o recriaria e os dados do banco seriam apagados.
resource "docker_volume" "mongo_data" {
  name = "todo-ebs-mongo-data"

  lifecycle {
    ignore_changes = [labels]
  }
}
