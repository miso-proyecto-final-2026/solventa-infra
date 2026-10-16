# T049: quitar un servicio retira su rol, deja sus esquemas reservados con datos y no emite DROP SCHEMA.

mock_provider "kubernetes" {}
mock_provider "kubectl" {}

variables {
  services = {
    "solventa-backend" = { role_name = "solventa_backend", owned_schemas = ["public"] }
  }
  # cotizacion se movió fuera: queda reservado, sin dueño.
  reserved_schemas = ["cotizacion", "identidad"]
  db = {
    host             = "postgres.example"
    admin_secret_ref = "rds!db-admin"
  }
  service_db_secret_names    = { "solventa-backend" = "solventa/staging/solventa-backend/db" }
  service_db_secret_versions = { "solventa-backend" = "v1" }
}

run "removed_service_role_is_retired_and_data_kept" {
  command = plan

  assert {
    condition     = strcontains(output.access_sql, "rolname <> ALL (ARRAY['solventa_backend']::name[])")
    error_message = "RULE removal: roles not in the list must be retired using the managed-by marker."
  }

  assert {
    condition     = strcontains(output.access_sql, "REASSIGN OWNED BY %I TO CURRENT_USER") && strcontains(output.access_sql, "DROP OWNED BY %I") && strcontains(output.access_sql, "DROP ROLE %I")
    error_message = "RULE removal: retired roles must reassign ownership before being dropped."
  }

  assert {
    condition     = !strcontains(output.access_sql, "DROP SCHEMA")
    error_message = "RULE removal: removing a service must never emit DROP SCHEMA."
  }

  assert {
    condition     = strcontains(output.access_sql, "CREATE SCHEMA IF NOT EXISTS \"cotizacion\";") && !strcontains(output.access_sql, "ALTER SCHEMA \"cotizacion\" OWNER TO")
    error_message = "RULE removal: the schema must remain, reserved and without a service owner."
  }
}
