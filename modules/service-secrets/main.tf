# Credenciales por servicio y de caché en Secrets Manager (E5). Los valores nunca salen de este módulo.

resource "random_password" "service_db" {
  for_each = var.services

  length  = 32
  special = false # solo [A-Za-z0-9] (contrato C2)
}

resource "aws_secretsmanager_secret" "service_db" {
  for_each = var.services

  name                    = "${var.secret_prefix}/${each.key}/db"
  description             = "Credenciales de base de datos de ${each.key}"
  recovery_window_in_days = 0 # permite recrear el nombre al día siguiente (research R16)

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "service_db" {
  for_each = var.services

  secret_id = aws_secretsmanager_secret.service_db[each.key].id

  secret_string = jsonencode({
    username = each.value.role_name
    password = random_password.service_db[each.key].result
    host     = var.db_host
    port     = tostring(var.db_port)
    dbname   = var.db_name
  })
}

resource "aws_secretsmanager_secret" "cache" {
  name                    = "${var.secret_prefix}/cache"
  description             = "Credenciales de la cache compartida"
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "cache" {
  secret_id = aws_secretsmanager_secret.cache.id

  secret_string = jsonencode({
    auth_token = var.cache_auth_token
    host       = var.cache_host
    port       = tostring(var.cache_port)
  })
}

# Secretos compartidos entre servicios (clave de servicio): el valor nace aquí y solo viaja por ESO.
resource "random_password" "shared" {
  for_each = var.shared_secret_names

  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "shared" {
  for_each = var.shared_secret_names

  name                    = each.key
  description             = "Secreto compartido entre servicios"
  recovery_window_in_days = 0

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "shared" {
  for_each = var.shared_secret_names

  secret_id     = aws_secretsmanager_secret.shared[each.key].id
  secret_string = jsonencode({ value = random_password.shared[each.key].result })
}
