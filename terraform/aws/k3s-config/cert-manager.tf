module "cert_manager" {
  source                = "terraform-iaac/cert-manager/kubernetes"
  create_namespace      = true
  namespace_name        = "cert-manager"
  cluster_issuer_create = false
  cluster_issuer_email  = var.admin_email
}

# Self-signed ClusterIssuer
resource "kubectl_manifest" "selfsigned_issuer" {
  yaml_body  = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-ca
spec:
  selfSigned: {}
YAML
  depends_on = [module.cert_manager]
}

# Root CA certificate (signed by selfsigned-ca)
resource "kubectl_manifest" "ca_root_cert" {
  yaml_body  = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ca-root
  namespace: cert-manager
spec:
  isCA: true
  commonName: my-ca
  secretName: ca-root-secret
  dnsNames:
    - ${var.main_domain}
  issuerRef:
    name: selfsigned-ca
    kind: ClusterIssuer
    group: cert-manager.io
YAML
  depends_on = [kubectl_manifest.selfsigned_issuer, module.cert_manager]
}

# CA ClusterIssuer (uses ca-root-secret)
resource "kubectl_manifest" "ca_issuer" {
  yaml_body  = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: local-issuer
spec:
  ca:
    secretName: ca-root-secret
YAML
  depends_on = [kubectl_manifest.ca_root_cert, module.cert_manager]
}
