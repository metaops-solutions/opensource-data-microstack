# Autogenerate bootstrap password and token
resource "random_password" "authentik_bootstrap_password" {
  length  = 32
  special = true
}

resource "random_password" "authentik_bootstrap_token" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "authentik_bootstrap" {
  name = "opensource-data-microstack-authentik-bootstrap-${random_id.suffix.hex}"
}

resource "aws_secretsmanager_secret_version" "authentik_bootstrap" {
  secret_id = aws_secretsmanager_secret.authentik_bootstrap.id
  secret_string = jsonencode({
    password = random_password.authentik_bootstrap_password.result
    token    = random_password.authentik_bootstrap_token.result
  })
}

data "aws_secretsmanager_secret_version" "authentik_bootstrap" {
  secret_id  = aws_secretsmanager_secret.authentik_bootstrap.id
  depends_on = [aws_secretsmanager_secret_version.authentik_bootstrap]
}
resource "kubernetes_namespace" "authentik" {
  metadata {
    name = "authentik"
  }
}

resource "random_password" "authentik_secret_key" {
  length  = 64
  special = true
}

resource "random_password" "authentik_postgres_password" {
  length  = 32
  special = true
}

resource "aws_secretsmanager_secret" "authentik_postgres" {
  name = "opensource-data-microstack-authentik-postgres-password-${random_id.suffix.hex}"
}

resource "aws_secretsmanager_secret_version" "authentik_postgres" {
  secret_id     = aws_secretsmanager_secret.authentik_postgres.id
  secret_string = random_password.authentik_postgres_password.result
}

data "aws_secretsmanager_secret_version" "authentik_postgres" {
  secret_id  = aws_secretsmanager_secret.authentik_postgres.id
  depends_on = [aws_secretsmanager_secret_version.authentik_postgres]
}

resource "kubernetes_secret" "authentik_secret" {
  metadata {
    name      = "authentik-secret"
    namespace = kubernetes_namespace.authentik.metadata[0].name
  }
  data = {
    AUTHENTIK_SECRET_KEY = random_password.authentik_secret_key.result
  }
}


resource "kubectl_manifest" "authentik_blueprint" {
  yaml_body = templatefile("${path.module}/authentik-config/authentik-blueprint-configmap.yaml", {
    authentik_hostname = var.authentik_hostname
    main_domain        = var.main_domain
  })

  depends_on = [
    kubernetes_namespace.authentik
  ]
}

resource "kubectl_manifest" "authentik_certificate" {
  yaml_body = templatefile("${path.module}/authentik-config/authentik-certificate.yaml", {
    authentik_hostname = var.authentik_hostname
  })

  depends_on = [
    kubernetes_namespace.authentik,
    kubectl_manifest.ca_issuer
  ]
}

resource "kubectl_manifest" "authentik_ingressroute" {
  yaml_body = templatefile("${path.module}/authentik-config/traefik-ingressroute.yaml", {
    authentik_hostname = var.authentik_hostname
  })

  depends_on = [
    kubernetes_namespace.authentik,
    kubectl_manifest.authentik_certificate
  ]
}

resource "helm_release" "authentik" {
  name             = "authentik"
  namespace        = kubernetes_namespace.authentik.metadata[0].name
  repository       = "https://charts.goauthentik.io"
  chart            = "authentik"
  version          = "2024.2.2"
  create_namespace = false
  values = [<<YAML
server:
  ingress:
    enabled: true
    ingressClassName: "traefik"
    hosts:
      - ${var.authentik_hostname}
    tls:
      - hosts:
          - ${var.authentik_hostname}
        secretName: authentik-tls
postgresql:
  enabled: false
authentik:
  enabled: true
  log_level: info
  secret_key: "${random_password.authentik_secret_key.result}"
  bootstrap_password: "${jsondecode(data.aws_secretsmanager_secret_version.authentik_bootstrap.secret_string)["password"]}"
  bootstrap_token: "${jsondecode(data.aws_secretsmanager_secret_version.authentik_bootstrap.secret_string)["token"]}"
  bootstrap_email: "${var.admin_email}"
  error_reporting:
    enabled: false
    environment: "k8s"
    send_pii: false
  postgresql:
    host: "postgres-postgresql.postgres.svc.cluster.local"
    port: 5432
    database: "authentik"
    user: "authentik"
    password: "${data.aws_secretsmanager_secret_version.authentik_postgres.secret_string}"
  redis:
    host: authentik-redis-master.authentik.svc.cluster.local
blueprints:
  enabled: true
  configMaps:
    - authentik-blueprint
redis:
  global:
    defaultStorageClass: longhorn
  enabled: true
  architecture: standalone
  auth:
    enabled: false
  master:
    storageClass: longhorn
    size: ${var.authentik_storage_size}
YAML
  ]
  depends_on = [
    kubectl_manifest.authentik_blueprint,
    kubectl_manifest.authentik_certificate,
    kubectl_manifest.authentik_ingressroute,
    kubernetes_secret.authentik_secret,
    helm_release.postgres,
    kubernetes_namespace.authentik
  ]
}
