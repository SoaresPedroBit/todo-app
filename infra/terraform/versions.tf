terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }

  # Estado local, fora do LocalStack: a edição Community perde tudo ao reiniciar,
  # e o estado precisa sobreviver a isso. O arquivo fica em infra/terraform/estado/
  # (não versionado) e o pipeline guarda uma cópia antes de cada alteração.
  backend "local" {
    path = "estado/terraform.tfstate"
  }
}

# "AWS" = LocalStack. Credenciais fictícias; o LocalStack não as valida.
provider "aws" {
  region                      = var.aws_region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    ec2            = var.aws_endpoint
    iam            = var.aws_endpoint
    sts            = var.aws_endpoint
    s3             = var.aws_endpoint
    secretsmanager = var.aws_endpoint
    ssm            = var.aws_endpoint
  }

  default_tags {
    tags = {
      Projeto  = "todo-app"
      Ambiente = var.environment
      Gerencia = "terraform"
    }
  }
}

# Docker local: executa as "VMs" correspondentes às instâncias EC2
provider "docker" {
  host = var.docker_host
}
