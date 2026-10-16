# T048: el SQL generado concede a cada rol solo los esquemas que posee; V2/V3/V4 fallan.

mock_provider "kubernetes" {}
mock_provider "kubectl" {}

variables {
  services = {
    "solventa-backend" = { role_name = "solventa_backend", owned_schemas = ["public", "cotizacion"] }
    "ms-prueba"        = { role_name = "ms_prueba", owned_schemas = ["identidad"] }
  }
  reserved_schemas = ["perfilamiento", "pagos"]
  drop_schemas     = []
  db = {
    host             = "postgres.example"
    admin_secret_ref = "rds!db-admin"
  }
  service_db_secret_names = {
    "solventa-backend" = "solventa/staging/solventa-backend/db"
    "ms-prueba"        = "solventa/staging/ms-prueba/db"
  }
  service_db_secret_versions = {
    "solventa-backend" = "v1"
    "ms-prueba"        = "v1"
  }
}

run "each_role_owns_only_its_schemas" {
  command = plan

  assert {
    condition     = strcontains(output.access_sql, "ALTER SCHEMA \"cotizacion\" OWNER TO \"solventa_backend\";")
    error_message = "RULE schema-ownership: cotizacion must be owned by solventa_backend."
  }

  assert {
    condition     = strcontains(output.access_sql, "ALTER SCHEMA \"identidad\" OWNER TO \"ms_prueba\";")
    error_message = "RULE schema-ownership: identidad must be owned by ms_prueba."
  }

  assert {
    condition     = strcontains(output.access_sql, "GRANT USAGE, CREATE ON SCHEMA public TO \"solventa_backend\";")
    error_message = "public must be granted to its owner (FR-015)."
  }

  assert {
    condition     = strcontains(output.access_sql, "REVOKE ALL ON SCHEMA \"cotizacion\" FROM \"ms_prueba\";") && strcontains(output.access_sql, "REVOKE ALL ON SCHEMA \"identidad\" FROM \"solventa_backend\";")
    error_message = "RULE schema-isolation: roles must lose access to schemas they do not own."
  }

  assert {
    condition     = strcontains(output.access_sql, "REVOKE ALL ON SCHEMA \"pagos\" FROM \"solventa_backend\";") && strcontains(output.access_sql, "REVOKE ALL ON SCHEMA \"pagos\" FROM \"ms_prueba\";")
    error_message = "RULE reserved-schemas: reserved schemas must have no grants for any service."
  }

  assert {
    condition     = !strcontains(output.access_sql, "ALTER SCHEMA \"pagos\" OWNER TO") && !strcontains(output.access_sql, "ALTER SCHEMA \"perfilamiento\" OWNER TO")
    error_message = "RULE reserved-schemas: reserved schemas must not be assigned to any service."
  }

  assert {
    condition     = !strcontains(output.access_sql, "PASSWORD '")
    error_message = "RULE secrets: passwords must never be part of the SQL text."
  }

  assert {
    condition     = !strcontains(output.access_sql, "DROP SCHEMA")
    error_message = "RULE no-drop: no schema may be dropped unless listed in drop_schemas."
  }
}

run "v2_schema_with_two_owners_fails" {
  command = plan

  variables {
    services = {
      "svc-a" = { role_name = "svc_a", owned_schemas = ["cotizacion"] }
      "svc-b" = { role_name = "svc_b", owned_schemas = ["cotizacion"] }
    }
    service_db_secret_names = { "svc-a" = "a", "svc-b" = "b" }
  }

  expect_failures = [var.services]
}

run "v3_reserved_and_owned_fails" {
  command = plan

  variables {
    reserved_schemas = ["cotizacion"]
  }

  expect_failures = [var.reserved_schemas]
}

run "v4_drop_owned_schema_fails" {
  command = plan

  variables {
    drop_schemas = ["cotizacion"]
  }

  expect_failures = [var.drop_schemas]
}

run "explicit_drop_of_unowned_schema_is_emitted" {
  command = plan

  variables {
    reserved_schemas = []
    drop_schemas     = ["legacy"]
  }

  assert {
    condition     = strcontains(output.access_sql, "DROP SCHEMA IF EXISTS \"legacy\" CASCADE;")
    error_message = "A schema listed in drop_schemas must be dropped explicitly (FR-016)."
  }
}
