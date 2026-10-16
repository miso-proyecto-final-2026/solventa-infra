# T020: escaneo al subir, tags inmutables, política de ciclo de vida y un repositorio por servicio.

mock_provider "aws" {}

variables {
  tags = {
    Project     = "solventa"
    Environment = "staging"
    Repository  = "miso-proyecto-final-2026/solventa-infra"
    ManagedBy   = "terraform"
    Stage       = "platform"
  }
}

run "one_hardened_repository_per_service" {
  command = plan

  variables {
    repositories = ["solventa-backend", "ms-prueba"]
  }

  assert {
    condition     = length(aws_ecr_repository.this) == 2
    error_message = "One ECR repository per service."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.image_scanning_configuration[0].scan_on_push])
    error_message = "RULE ecr-scan: scan_on_push must be enabled (FR-010)."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.image_tag_mutability == "IMMUTABLE"])
    error_message = "RULE ecr-immutable: tags must be IMMUTABLE."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : r.force_delete])
    error_message = "RULE ecr-teardown: force_delete must be true for on-demand teardown."
  }

  assert {
    condition     = alltrue([for k, p in aws_ecr_lifecycle_policy.this : length(jsondecode(p.policy).rules) == 2])
    error_message = "Each repository needs the untagged-expiry and keep-last-N lifecycle rules."
  }

  assert {
    condition     = alltrue([for r in aws_ecr_repository.this : alltrue([for k in ["Project", "Environment", "Repository", "ManagedBy", "Stage"] : contains(keys(r.tags), k)])])
    error_message = "RULE tags: every resource must carry the five mandatory tags."
  }
}
