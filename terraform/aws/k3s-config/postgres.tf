# Generate random password for Airbyte DB user
resource "random_password" "airbyte" {
  length  = 20
  special = true
}

resource "kubernetes_namespace" "postgres" {
  metadata {
    name = "postgres"
  }
}

resource "random_password" "postgres" {
  length  = 20
  special = true
}

# Store password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "postgres" {
  name = "opensource-data-microstack-postgres-password-${random_id.suffix.hex}"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id     = aws_secretsmanager_secret.postgres.id
  secret_string = random_password.postgres.result
}

data "aws_secretsmanager_secret_version" "postgres" {
  secret_id  = aws_secretsmanager_secret.postgres.id
  depends_on = [aws_secretsmanager_secret_version.postgres]

}

# ConfigMap for Postgres init scripts
resource "kubernetes_config_map" "postgres_init" {
  metadata {
    name      = "postgresql-init"
    namespace = kubernetes_namespace.postgres.metadata[0].name
  }
  data = {
    "init.sql" = <<-EOT
      CREATE USER airbyte WITH PASSWORD '${data.aws_secretsmanager_secret_version.airbyte.secret_string}' CREATEDB;
      CREATE DATABASE airbyte OWNER airbyte;
      CREATE USER authentik WITH PASSWORD '${data.aws_secretsmanager_secret_version.authentik_postgres.secret_string}';
      CREATE DATABASE authentik OWNER authentik;
      CREATE USER metabase WITH PASSWORD '${data.aws_secretsmanager_secret_version.metabase.secret_string}' CREATEDB;
      CREATE DATABASE metabase OWNER metabase;
    EOT
  }
}

resource "helm_release" "postgres" {
  name             = "postgres"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "postgresql"
  version          = "15.5.2"
  namespace        = kubernetes_namespace.postgres.metadata[0].name
  create_namespace = false

  set = [
    {
      name  = "auth.postgresPassword"
      value = data.aws_secretsmanager_secret_version.postgres.secret_string
    },
    {
      name  = "primary.persistence.storageClass"
      value = "longhorn"
    },
    {
      name  = "primary.persistence.size"
      value = var.postgres_primary_persistence_size
    },
    {
      name  = "primary.initdb.scriptsConfigMap"
      value = kubernetes_config_map.postgres_init.metadata[0].name
    }
  ]
  depends_on = [
    kubernetes_config_map.postgres_init
  ]
}

