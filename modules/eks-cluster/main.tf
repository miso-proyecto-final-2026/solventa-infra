locals {
  admin_policy = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  view_policy  = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  admin_entries = {
    for i, arn in var.cluster_admin_principal_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = local.admin_policy
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  plan_entries = var.plan_role_arn == null ? {} : {
    ci-plan = {
      principal_arn = var.plan_role_arn
      policy_associations = {
        view = {
          policy_arn   = local.view_policy
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Configuración del endpoint y de la política de soporte; los tests verifican estos valores (FR-011, FR-011a).
  endpoint = {
    public       = true
    private      = true
    public_cidrs = var.api_allowed_cidrs
  }
  support_type = "STANDARD"

  # Los roles de despliegue no reciben política de EKS: solo el grupo, que se enlaza por RoleBinding en `staging`.
  deployer_entries = {
    for svc, arn in var.deployer_role_arns : "deploy-${svc}" => {
      principal_arn     = arn
      kubernetes_groups = [var.deployers_group]
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  endpoint_public_access       = local.endpoint.public
  endpoint_private_access      = local.endpoint.private
  endpoint_public_access_cidrs = local.endpoint.public_cidrs

  # Soporte estándar: el soporte extendido cuesta seis veces más (research R5).
  upgrade_policy = {
    support_type = local.support_type
  }

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries                           = merge(local.admin_entries, local.plan_entries, local.deployer_entries)

  enable_irsa = false # el acceso a AWS de las cargas usa EKS Pod Identity

  enabled_log_types                      = var.enable_control_plane_logging ? ["api", "audit", "authenticator"] : []
  create_cloudwatch_log_group            = var.enable_control_plane_logging
  cloudwatch_log_group_retention_in_days = 7

  addons = {
    eks-pod-identity-agent = {
      before_compute = true
    }
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]

      min_size     = var.node_count
      max_size     = max(var.node_max_count, var.node_count)
      desired_size = var.node_count

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.node_disk_size_gib
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }

  tags = var.tags
}
