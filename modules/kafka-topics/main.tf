# Job que crea los topics del bus de eventos desde dentro de la VPC (el clúster MSK es privado), como db-access con la BD.
# Idempotente: si un topic ya existe se deja como está. Un cambio en los topics, en el script o en los brokers genera un Job nuevo.

locals {
  # Cada topic con DLQ añade <topic>.dlq (una partición): es donde caen los eventos que un consumidor no pudo procesar.
  all_topics = merge(
    {
      for name, t in var.topics : name => {
        partitions         = t.partitions
        retention_ms       = t.retention_hours * 3600 * 1000
        replication_factor = var.replication_factor
      }
    },
    {
      for name, t in var.topics : "${name}.dlq" => {
        partitions         = 1
        retention_ms       = t.retention_hours * 3600 * 1000
        replication_factor = var.replication_factor
      } if t.dlq
    },
  )

  topics_json = jsonencode(local.all_topics)
  script      = file("${path.module}/templates/crear_topics.py")
  job_hash    = substr(sha256(join("|", [local.topics_json, local.script, var.bootstrap_servers])), 0, 10)

  # Versiones exactas: el Job instala las librerías al arrancar y no debe cambiar de comportamiento sin que se note.
  pip_install = "pip install --no-cache-dir --disable-pip-version-check aiokafka==0.14.0 aws-msk-iam-sasl-signer-python==1.0.2"
}

resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = var.service_account
    namespace = var.namespace
  }
}

resource "kubernetes_config_map_v1" "topics" {
  metadata {
    name      = "kafka-topics-${local.job_hash}"
    namespace = var.namespace
  }

  data = {
    "topics.json"     = local.topics_json
    "crear_topics.py" = local.script
  }
}

resource "kubernetes_job_v1" "topics" {
  metadata {
    name      = "kafka-topics-${local.job_hash}"
    namespace = var.namespace

    labels = {
      "app.kubernetes.io/name"      = "kafka-topics"
      "app.kubernetes.io/component" = "platform"
    }
  }

  spec {
    backoff_limit = 3

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "kafka-topics"
        }
      }

      spec {
        restart_policy       = "OnFailure"
        service_account_name = kubernetes_service_account_v1.this.metadata[0].name

        container {
          name    = "crear-topics"
          image   = var.image
          command = ["sh", "-c", "${local.pip_install} && python /app/crear_topics.py /app/topics.json"]

          env {
            name  = "KAFKA_BOOTSTRAP_SERVERS"
            value = var.bootstrap_servers
          }

          env {
            name  = "AWS_REGION"
            value = var.region
          }

          volume_mount {
            name       = "topics"
            mount_path = "/app"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "topics"
          config_map {
            name = kubernetes_config_map_v1.topics.metadata[0].name
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = var.job_timeout
    update = var.job_timeout
  }
}
