#!/bin/bash
set -e

# Load environment variables
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo ".env file not found! Please create it from .env.example."
  set -e
fi

# Remove local CA certificate from keychain
remove_local_ca() {
  if [ -f ./k3s-data/local-ca.crt ]; then
    echo "Removing local CA certificate from macOS System Keychain (requires sudo)..."
    sudo security delete-certificate -c "local-ca.crt" /Library/Keychains/System.keychain || true
    rm -f ./k3s-data/local-ca.crt
  fi
}

# Delete k3d cluster
delete_cluster() {
  echo "Deleting k3d cluster '${K3D_CLUSTER_NAME}'..."
  k3d cluster delete "${K3D_CLUSTER_NAME}"
  # remove_local_ca
  rm -rf ./k3s-data
}

# Optional argument to delete the k3d cluster
if [[ "$1" == "recreate" ]]; then
  delete_cluster
  echo "Cluster deleted. Continuing setup..."
fi

# Optional argument to only delete the k3d cluster and exit
if [[ "$1" == "delete-only" ]]; then
  delete_cluster
  echo "Cluster deleted. Exiting."
  exit 0
fi

# Install k3d
if ! command -v brew &> /dev/null; then
  echo "Homebrew not found! Please install Homebrew first."
  exit 1
fi
if ! command -v k3d &> /dev/null; then
  echo "k3d not found! Installing k3d via Homebrew..."
  brew install k3d
fi

# Temp directory for k3s data like pvc's and other temporary files
mkdir -p ./k3s-data

# Create k3d cluster if it doesn't exist
if ! k3d cluster list | grep -q "^${K3D_CLUSTER_NAME}" || [ $(k3d node list | grep "k3d-${K3D_CLUSTER_NAME}" | wc -l) -eq 0 ]; then
  echo "Creating k3d cluster '${K3D_CLUSTER_NAME}' with host volume mount for local-path storage..."
  k3d cluster delete "${K3D_CLUSTER_NAME}" 2>/dev/null || true
  k3d cluster create "${K3D_CLUSTER_NAME}" --api-port 6550 --volume $(pwd)/k3s-data:/var/lib/rancher/k3s/storage --k3s-arg "--disable=traefik@server:0" --port 443:32443@loadbalancer
else
  echo "k3d cluster '${K3D_CLUSTER_NAME}' already exists and has nodes."
fi
export KUBECONFIG=$(k3d kubeconfig write "${K3D_CLUSTER_NAME}")

# Check if KUBECONFIG is set
echo "Kubeconfig set to: $KUBECONFIG"
if [ -z "$KUBECONFIG" ] || [ ! -f "$KUBECONFIG" ]; then
  echo "DEBUG: Kubeconfig is not set or file does not exist."
  echo "Intended kubeconfig path: $KUBECONFIG"
  echo "You may need to recreate the k3d cluster or check k3d logs."
  exit 1
fi

# Guard rail: ensure current context is the intended k3d cluster
CURRENT_CONTEXT=$(kubectl config current-context)
EXPECTED_CONTEXT="k3d-${K3D_CLUSTER_NAME}"
if [ "$CURRENT_CONTEXT" != "$EXPECTED_CONTEXT" ]; then
  echo "ERROR: Current kubeconfig context ($CURRENT_CONTEXT) does not match expected k3d cluster ($EXPECTED_CONTEXT)."
  echo "Aborting to prevent accidental deployment to the wrong cluster."
  exit 1
fi

# Install Traefik via Helm (custom NodePort values)
helm repo add traefik https://helm.traefik.io/traefik >> /dev/null
helm repo update >> /dev/null
helm upgrade traefik traefik/traefik --install --wait \
--namespace traefik --create-namespace \
-f ./traefik.values.yaml

# Install cert-manager before applying cert-manager resources
helm repo add jetstack https://charts.jetstack.io >> /dev/null
helm repo update >> /dev/null
helm upgrade cert-manager jetstack/cert-manager --install --wait \
  --namespace cert-manager --create-namespace \
  --version v1.14.4 \
  --set installCRDs=true

# Wait for cert-manager CRDs to be ready
echo "Waiting for cert-manager CRDs to be established..."
kubectl wait --for=condition=Established --timeout=60s crd/certificates.cert-manager.io || true
kubectl wait --for=condition=Established --timeout=60s crd/clusterissuers.cert-manager.io || true




# Apply cert-manager manifests from files
echo "Applying cert-manager manifests..."
envsubst < ./cert-manager/selfsigned-ca.yaml | kubectl apply -f -
envsubst < ./cert-manager/local-issuer.yaml | kubectl apply -f -
envsubst < ./cert-manager/ca-root-certificate.yaml | kubectl apply -f -

# Add ingress hostnames to /etc/hosts
echo "Adding ingress hostnames to /etc/hosts (requires sudo)..."
HOSTS=("$AIRBYTE_HOST" "$AUTHENTIK_HOST" "$METABASE_HOST")
for HOST in "${HOSTS[@]}"; do
  if ! grep -q "127.0.0.1[[:space:]]$HOST" /etc/hosts; then
    echo "Adding $HOST to /etc/hosts"
    echo "127.0.0.1 $HOST" | sudo tee -a /etc/hosts > /dev/null
  else
    echo "$HOST already present in /etc/hosts"
  fi
done

# Create ConfigMap for Postgres init scripts
kubectl create namespace postgres --dry-run=client -o yaml | kubectl apply -f -
envsubst < ./postgres/postgresql-init-configmap.yaml | kubectl apply -f -

# Install Postgres with init script
helm repo add bitnami https://charts.bitnami.com/bitnami >> /dev/null
helm repo update >> /dev/null
helm upgrade postgres bitnami/postgresql --install --wait \
  --namespace postgres --create-namespace \
  --version 15.5.2 \
  --set auth.postgresPassword=${POSTGRES_DB_PASSWORD} \
  --set primary.persistence.storageClass=local-path \
  --set primary.persistence.size=${POSTGRES_DB_SIZE} \
  --set primary.initdb.scriptsConfigMap=postgresql-init

# Install Airbyte
helm repo add airbyte https://airbytehq.github.io/helm-charts >> /dev/null
helm repo update >> /dev/null
helm upgrade airbyte airbyte/airbyte --install --wait \
  --namespace airbyte --create-namespace \
  --version 0.199.0 \
  --set global.database.user=${AIRBYTE_DB_USER} \
  --set global.database.password=${AIRBYTE_DB_PASSWORD} \
  --set global.database.database=${AIRBYTE_DB_NAME} \
  --set global.database.host=${AIRBYTE_DB_HOST} \
  --set global.database.port=${AIRBYTE_DB_PORT} \
  --set minio.storage.storageClass=local-path \
  --set minio.storage.volumeClaimValue=${MINIO_STORAGE_SIZE} \
  --set keycloak.enabled=false \
  --set postgresql.enabled=false

## Install Metabase
### There is not offcial chart of metabase.
helm repo add pmint93 https://pmint93.github.io/helm-charts >> /dev/null
helm repo update >> /dev/null
helm upgrade metabase pmint93/metabase --install --wait \
  --namespace metabase --create-namespace \
  --set database.type=postgres \
  --set database.dbname=metabase \
  --set database.host=postgres-postgresql.postgres.svc.cluster.local \
  --set database.port=5432 \
  --set database.username=${METABASE_DB_USER} \
  --set database.password=${METABASE_DB_PASSWORD} \
  --set ingress.enabled=true \
  --set ingress.hosts[0]=metabase.metaops.solutions.local \
  --set ingress.tls[0].hosts[0]=metabase.metaops.solutions.local \
  --set ingress.tls[0].secretName=metabase-tls

echo "Applying Airbyte manifests with envsubst..."
envsubst < ./airbyte/airbyte-certificate.yaml | kubectl apply -f -
envsubst < ./airbyte/traefik-forwardauth.yaml | kubectl apply -f -
envsubst < ./airbyte/traefik-ingressroute.yaml | kubectl apply -f -

# Install Authentik
kubectl create ns authentik --dry-run=client -o yaml | kubectl apply -f -
envsubst < ./authentik/authentik-blueprint-configmap.yaml | kubectl apply -f -
helm repo add authentik https://charts.goauthentik.io >> /dev/null
helm repo update >> /dev/null
helm upgrade authentik authentik/authentik --install --wait \
  --namespace authentik --install --create-namespace \
  --version 2024.2.2 \
  --set server.ingress.enabled=true \
  --set server.ingress.hosts[0]=authentik.metaops.solutions.local \
  --set server.ingress.tls[0].hosts[0]=authentik.metaops.solutions.local \
  --set server.ingress.tls[0].secretName=authentik-tls \
  --set postgresql.enabled=false \
  --set authentik.enabled=true \
  --set authentik.log_level=info \
  --set authentik.secret_key=${AUTHENTIK_SECRET_KEY} \
  --set authentik.bootstrap_password=${AUTHENTIK_BOOTSTRAP_PASSWORD} \
  --set authentik.bootstrap_token=${AUTHENTIK_BOOTSTRAP_TOKEN} \
  --set authentik.bootstrap_email=${AUTHENTIK_ADMIN_EMAIL} \
  --set authentik.postgresql.host=${AUTHENTIK_DB_HOST} \
  --set authentik.postgresql.port=\"${AUTHENTIK_DB_PORT}\" \
  --set authentik.postgresql.database=${AUTHENTIK_DB_NAME} \
  --set authentik.postgresql.user=${AUTHENTIK_DB_USER} \
  --set authentik.postgresql.password=${AUTHENTIK_DB_PASSWORD} \
  --set redis.global.defaultStorageClass=local-path \
  --set redis.enabled=true \
  --set redis.architecture=standalone \
  --set redis.auth.enabled=false \
  --set redis.master.storageClass=local-path \
  --set redis.master.size=8Gi \
  --set blueprints.enabled=true \
  --set blueprints.configMaps[0]=authentik-blueprint

echo "Applying Authentik manifests with envsubst..."
envsubst < ./authentik/authentik-certificate.yaml | kubectl apply -f -
envsubst < ./authentik/traefik-ingressroute.yaml | kubectl apply -f -

echo "All services installed successfully!"

# # Extract CA certificate and add to macOS System Keychain
# echo "Extracting local CA certificate from Kubernetes..."
# kubectl get secret ca-root-secret -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 --decode > ./k3s-data/local-ca.crt
# echo "Adding local CA certificate to macOS System Keychain (requires sudo)..."
# sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./k3s-data/local-ca.crt