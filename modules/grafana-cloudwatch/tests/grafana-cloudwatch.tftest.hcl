# Grafana lee métricas de CloudWatch con Pod Identity y solo lectura.

mock_provider "aws" {}

variables {
  cluster_name = "solventa-staging"
}

run "grafana_reads_metrics_only_through_pod_identity" {
  command = plan

  assert {
    condition = (
      aws_eks_pod_identity_association.grafana.namespace == "monitoring"
      && aws_eks_pod_identity_association.grafana.service_account == "grafana"
      && jsondecode(aws_iam_role.grafana.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    )
    error_message = "RULE grafana-cloudwatch-identity: the role must be bound to the grafana service account by Pod Identity."
  }

  assert {
    condition = alltrue([
      for a in jsondecode(aws_iam_role_policy.grafana.policy).Statement[0].Action : startswith(a, "cloudwatch:List") || startswith(a, "cloudwatch:Get") || startswith(a, "cloudwatch:Describe")
    ])
    error_message = "RULE grafana-cloudwatch-readonly: Grafana may only read CloudWatch metrics."
  }
}
