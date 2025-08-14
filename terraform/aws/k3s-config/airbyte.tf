# Store Airbyte DB password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "airbyte" {
  name = "opensource-data-microstack-airbyte-db-password-${random_id.suffix.hex}"
}

resource "aws_secretsmanager_secret_version" "airbyte" {
  secret_id     = aws_secretsmanager_secret.airbyte.id
  secret_string = random_password.airbyte.result
}

# Fetch Airbyte DB password from Secrets Manager
data "aws_secretsmanager_secret_version" "airbyte" {
  secret_id  = aws_secretsmanager_secret.airbyte.id
  depends_on = [aws_secretsmanager_secret_version.airbyte]
}

resource "helm_release" "airbyte" {
  name             = "airbyte"
  repository       = "https://airbytehq.github.io/helm-charts"
  chart            = "airbyte"
  version          = "0.199.0"
  namespace        = "airbyte"
  create_namespace = true
  set = [
    {
      name  = "global.database.user"
      value = "airbyte"
    },
    {
      name  = "global.database.password"
      value = data.aws_secretsmanager_secret_version.airbyte.secret_string
    },
    {
      name  = "global.database.database"
      value = "airbyte"
    },
    {
      name  = "global.database.host"
      value = "postgres-postgresql.postgres.svc.cluster.local"
    },
    {
      name  = "global.database.port"
      value = "5432"
    },
    {
      name  = "minio.storage.storageClass"
      value = "longhorn"
    },
    {
      name  = "minio.storage.volumeClaimValue"
      value = var.minio_storage_volume_claim_value
    },
    {
      name  = "keycloak.enabled"
      value = "false"
    },
    {
      name  = "postgresql.enabled"
      value = "false"
    }
  ]
  depends_on = [
    helm_release.postgres
  ]
}

resource "kubectl_manifest" "airbyte_certificate" {
  yaml_body = templatefile("${path.module}/airbyte-config/airbyte-certificate.yaml", {
    airbyte_hostname = var.airbyte_hostname
  })

  depends_on = [
    helm_release.airbyte,
    kubectl_manifest.ca_issuer
  ]
}

resource "kubectl_manifest" "airbyte_forwardauth" {
  yaml_body = file("${path.module}/airbyte-config/traefik-forwardauth.yaml")

  depends_on = [
    helm_release.airbyte
  ]
}

resource "kubectl_manifest" "airbyte_ingressroute" {
  yaml_body = templatefile("${path.module}/airbyte-config/traefik-ingressroute.yaml", {
    airbyte_hostname = var.airbyte_hostname
  })

  depends_on = [
    helm_release.airbyte,
    kubectl_manifest.airbyte_certificate
  ]
}
