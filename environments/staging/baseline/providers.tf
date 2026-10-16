provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "solventa"
      Environment = "staging"
      Repository  = "miso-proyecto-final-2026/solventa-infra"
      ManagedBy   = "terraform"
      Stage       = "baseline"
    }
  }
}

# Los proveedores del clúster se configuran con la salida de la etapa platform (research R4).
locals {
  cluster_endpoint = local.platform.cluster_endpoint
  cluster_ca       = base64decode(local.platform.cluster_ca_data)
  token_args       = ["eks", "get-token", "--cluster-name", local.platform.cluster_name, "--region", local.platform.region]
}

provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = local.cluster_ca

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.token_args
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = local.cluster_ca

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = local.token_args
    }
  }
}

provider "kubectl" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = local.cluster_ca
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = local.token_args
  }
}
