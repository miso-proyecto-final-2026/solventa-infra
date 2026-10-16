terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }

  # Primer apply con estado local; luego `terraform init -migrate-state` hacia el bucket creado
  # (descomentar y completar `bucket`, ver README "Bootstrap").
  # backend "s3" {
  #   key          = "bootstrap/terraform.tfstate"
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "solventa"
      Environment = "bootstrap"
      Repository  = "miso-proyecto-final-2026/solventa-infra"
      ManagedBy   = "terraform"
      Stage       = "bootstrap"
    }
  }
}
