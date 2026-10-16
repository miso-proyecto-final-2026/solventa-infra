terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Configuración parcial: bucket y región llegan por -backend-config=../backend.hcl (README "Provisión").
  backend "s3" {
    key          = "staging/platform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
