# Proveedor AWS apuntando al servidor Moto (research R13). Credenciales ficticias: nunca llega nada a AWS.
provider "aws" {
  region     = var.region
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    ec2            = var.moto_endpoint
    ecr            = var.moto_endpoint
    iam            = var.moto_endpoint
    s3             = var.moto_endpoint
    secretsmanager = var.moto_endpoint
    sts            = var.moto_endpoint
  }

  default_tags {
    tags = local.tags
  }
}
