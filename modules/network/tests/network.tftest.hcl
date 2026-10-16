# T016: la red cubre al menos 2 AZ con subredes públicas y privadas y etiquetas obligatorias.

mock_provider "aws" {}

override_data {
  target = data.aws_availability_zones.available
  values = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
}

override_data {
  target = data.aws_region.current
  values = { region = "us-east-1" }
}

variables {
  tags = {
    Project     = "solventa"
    Environment = "staging"
    Repository  = "miso-proyecto-final-2026/solventa-infra"
    ManagedBy   = "terraform"
    Stage       = "platform"
  }
}

run "two_azs_with_public_and_private_subnets" {
  command = plan

  assert {
    condition     = length(output.azs) == 2 && length(local.private_subnets) == 2 && length(local.public_subnets) == 2
    error_message = "RULE network-az: at least 2 AZs with one public and one private subnet each."
  }

  assert {
    condition     = alltrue([for c in local.private_subnets : endswith(c, "/20")])
    error_message = "Subnets must be /20."
  }

  assert {
    condition     = aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway"
    error_message = "The S3 endpoint must be a gateway endpoint."
  }

  assert {
    condition     = alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(aws_vpc_endpoint.s3.tags), k)])
    error_message = "RULE tags: every resource must carry the five mandatory tags."
  }
}

run "single_az_is_rejected" {
  command = plan

  variables {
    az_count = 1
  }

  expect_failures = [var.az_count]
}
