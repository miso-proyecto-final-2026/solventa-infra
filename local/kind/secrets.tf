# Secrets de origen en el namespace local-secrets: hacen el papel de Secrets Manager (research R9).
# Mismas claves que en AWS: username, password, host, port, dbname.

resource "kubernetes_namespace_v1" "local_secrets" {
  metadata {
    name = "local-secrets"
  }
}

resource "random_password" "pg_admin" {
  length  = 32
  special = false
}

resource "random_password" "service_db" {
  for_each = module.service_list.services

  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "pg_admin" {
  metadata {
    name      = "pg-admin"
    namespace = kubernetes_namespace_v1.local_secrets.metadata[0].name
  }

  data = {
    username = "postgres"
    password = random_password.pg_admin.result
  }
}

resource "kubernetes_secret_v1" "service_db" {
  for_each = module.service_list.services

  metadata {
    name      = "${each.key}-db"
    namespace = kubernetes_namespace_v1.local_secrets.metadata[0].name
  }

  data = {
    username = each.value.role_name
    password = random_password.service_db[each.key].result
    host     = "postgres.local-deps.svc"
    port     = "5432"
    dbname   = "solventa"
  }
}
