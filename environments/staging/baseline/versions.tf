terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }

  # Configuración parcial: bucket y región llegan por -backend-config=../backend.hcl (README "Baseline").
  backend "s3" {
    key          = "staging/baseline.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
