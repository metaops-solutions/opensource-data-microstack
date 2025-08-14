# Helm release for Longhorn (block storage for Kubernetes)
resource "helm_release" "longhorn" {
  name             = "longhorn"
  repository       = "https://charts.longhorn.io"
  chart            = "longhorn"
  version          = "1.6.2"
  namespace        = "longhorn-system"
  create_namespace = true

  set = [
    {
      name  = "defaultSettings.defaultReplicaCount"
      value = var.longhorn_default_replica_count
    },
    {
      name  = "defaultSettings.defaultDataPath"
      value = "/mnt/data"
    }
  ]
}

