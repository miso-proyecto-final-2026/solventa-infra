# HS2: los topics del contrato se crean desde dentro de la VPC con un Job (el clúster es privado).

mock_provider "kubernetes" {}

variables {
  bootstrap_servers = "b-1.eventos.abc.kafka.us-east-1.amazonaws.com:9098,b-2.eventos.abc.kafka.us-east-1.amazonaws.com:9098"
  region            = "us-east-1"
  topics = {
    "solventa.a.comandos"   = { partitions = 3, retention_hours = 168, dlq = true }
    "solventa.b.resultados" = { partitions = 6, retention_hours = 24, dlq = false }
  }
}

run "topics_include_dead_letter_queues_only_when_asked" {
  command = plan

  assert {
    condition     = contains(keys(output.all_topics), "solventa.a.comandos") && contains(keys(output.all_topics), "solventa.a.comandos.dlq")
    error_message = "A topic with dlq = true also gets <topic>.dlq."
  }

  assert {
    condition     = contains(keys(output.all_topics), "solventa.b.resultados") && !contains(keys(output.all_topics), "solventa.b.resultados.dlq")
    error_message = "A topic with dlq = false gets no dead-letter queue."
  }

  assert {
    condition     = output.all_topics["solventa.b.resultados"].partitions == 6 && output.all_topics["solventa.b.resultados"].retention_ms == 24 * 3600 * 1000
    error_message = "Partitions and retention come from the topic declaration (hours converted to ms)."
  }

  assert {
    condition     = output.all_topics["solventa.a.comandos.dlq"].partitions == 1
    error_message = "A dead-letter queue has a single partition."
  }

  assert {
    condition     = alltrue([for t in values(output.all_topics) : t.replication_factor == 2])
    error_message = "Replication factor 2 (two brokers)."
  }
}

run "job_runs_with_the_topic_admin_identity_and_no_secrets" {
  command = plan

  assert {
    condition     = kubernetes_service_account_v1.this.metadata[0].name == "kafka-topics" && kubernetes_service_account_v1.this.metadata[0].namespace == "solventa-system"
    error_message = "RULE kafka-topics-identity: the Job runs as kafka-topics in solventa-system (the Pod Identity association from the platform)."
  }

  assert {
    condition     = kubernetes_job_v1.topics.spec[0].template[0].spec[0].service_account_name == "kafka-topics"
    error_message = "The Job must use the kafka-topics service account."
  }

  assert {
    condition     = length(kubernetes_job_v1.topics.spec[0].template[0].spec[0].container[0].env_from) == 0
    error_message = "RULE kafka-topics-secrets: the Job needs no secret; IAM is its only credential."
  }

  assert {
    condition     = kubernetes_job_v1.topics.spec[0].template[0].spec[0].container[0].security_context[0].allow_privilege_escalation == false
    error_message = "The Job must not allow privilege escalation."
  }
}

run "versions_of_the_client_libraries_are_pinned" {
  command = plan

  assert {
    condition     = can(regex("aiokafka==[0-9]+\\.[0-9]+\\.[0-9]+", join(" ", kubernetes_job_v1.topics.spec[0].template[0].spec[0].container[0].command))) && can(regex("aws-msk-iam-sasl-signer-python==[0-9]+\\.[0-9]+\\.[0-9]+", join(" ", kubernetes_job_v1.topics.spec[0].template[0].spec[0].container[0].command)))
    error_message = "RULE kafka-topics-pin: the client libraries are installed with exact versions."
  }
}

run "a_change_in_the_topics_creates_a_new_job" {
  command = plan

  assert {
    condition     = can(regex("^kafka-topics-[0-9a-f]{10}$", kubernetes_job_v1.topics.metadata[0].name))
    error_message = "The Job name carries a hash of its inputs so a change re-runs it and no change does not."
  }
}

run "bootstrap_servers_are_required" {
  command = plan

  variables {
    bootstrap_servers = ""
  }

  expect_failures = [var.bootstrap_servers]
}
