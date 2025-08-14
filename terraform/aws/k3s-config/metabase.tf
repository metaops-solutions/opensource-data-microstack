# Generate random password for Metabase DB user
resource "random_password" "metabase" {
  length  = 20
  special = true
}

# Store Metabase DB password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "metabase" {
  name = "opensource-data-microstack-metabase-db-password-${random_id.suffix.hex}"
}

resource "aws_secretsmanager_secret_version" "metabase" {
  secret_id     = aws_secretsmanager_secret.metabase.id
  secret_string = random_password.metabase.result
}

data "aws_secretsmanager_secret_version" "metabase" {
  secret_id  = aws_secretsmanager_secret.metabase.id
  depends_on = [aws_secretsmanager_secret_version.metabase]
}

resource "helm_release" "metabase" {
  name             = "metabase"
  repository       = "https://pmint93.github.io/helm-charts"
  chart            = "metabase"
  namespace        = "metabase"
  create_namespace = true
  set = [
    {
      name  = "database.type"
      value = "postgres"
    },
    {
      name  = "database.dbname"
      value = "metabase"
    },
    {
      name  = "database.host"
      value = "postgres-postgresql.postgres.svc.cluster.local"
    },
    {
      name  = "database.port"
      value = "5432"
    },
    {
      name  = "database.username"
      value = "metabase"
    },
    {
      name  = "database.password"
      value = data.aws_secretsmanager_secret_version.metabase.secret_string
    },
    {
      name  = "ingress.enabled"
      value = "true"
    },
    {
      name  = "ingress.hosts[0]"
      value = var.metabase_hostname
    },
    {
      name  = "ingress.tls[0].hosts[0]"
      value = var.metabase_hostname
    },
    {
      name  = "ingress.tls[0].secretName"
      value = "metabase-tls"
    }
  ]

  depends_on = [
    helm_release.postgres,
    kubectl_manifest.ca_issuer
  ]
}
