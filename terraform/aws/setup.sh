#!/bin/bash
set -ex

# Function to run terraform apply in a directory
terraform_apply() {
  local dir="$1"
  cd "$dir"
  if ! terraform init; then
    echo "ERROR: terraform init failed in $dir. Exiting."
    exit 1
  fi
  if ! terraform workspace list | grep -q "lab"; then
    terraform workspace new lab
  else
    terraform workspace select lab
  fi
  terraform apply --auto-approve
  terraform output -json > outputs.json
  cd - > /dev/null
}

# Function to run terraform destroy in a directory
terraform_destroy() {
  local dir="$1"
  local resource="$2"
  cd "$dir"
  if ! terraform init; then
    echo "ERROR: terraform init failed in $dir. Exiting."
    exit 1
  fi
  if ! terraform workspace list | grep -q "lab"; then
    terraform workspace new lab
  else
    terraform workspace select lab
  fi
  if [[ -n "$resource" ]]; then
    terraform state rm "$resource" || true
  fi
  terraform destroy --auto-approve
  cd - > /dev/null
}

# Function to update /etc/hosts with EC2 IP and hostnames
update_hosts() {
  # Read outputs from JSON files
  local ip=$(jq -r '.instance_ip.value' cloud-resources/outputs.json)
  local airbyte_host=$(jq -r '.airbyte_hostname.value' k3s-config/outputs.json)
  local metabase_host=$(jq -r '.metabase_hostname.value' k3s-config/outputs.json)
  local authentik_host=$(jq -r '.authentik_hostname.value' k3s-config/outputs.json)

  # Fallback to default hostnames if not found
  airbyte_host=${airbyte_host:-airbyte.metaops.solutions.local}
  metabase_host=${metabase_host:-metabase.metaops.solutions.local}
  authentik_host=${authentik_host:-authentik.metaops.solutions.local}

  # Only proceed if IP is found
  if [[ -z "$ip" ]]; then
    echo "Could not find EC2 instance IP from Terraform outputs. Skipping /etc/hosts update."
    return
  fi

  # Function to add or update a host entry
  add_or_update_host() {
    local ip="$1"
    local host="$2"
    if grep -q "[[:space:]]$host" /etc/hosts; then
      sudo sed -i.bak "/[[:space:]]$host/d" /etc/hosts
    fi
    echo "$ip $host" | sudo tee -a /etc/hosts > /dev/null
  }

  add_or_update_host "$ip" "$airbyte_host"
  add_or_update_host "$ip" "$metabase_host"
  add_or_update_host "$ip" "$authentik_host"
  echo "/etc/hosts updated with EC2 IP and hostnames."
}

# Ensure yq is installed for kubeconfig patching
if ! command -v yq &> /dev/null; then
  if command -v brew &> /dev/null; then
    brew install yq
  else
    echo "Please install yq manually."; exit 1;
  fi
fi

# Set AWS region to Europe (London)
export AWS_DEFAULT_REGION="eu-west-2"

# Suppress AWS CLI output and disable pager globally
export AWS_PAGER=""
export AWS_DEFAULT_OUTPUT="text"

# Check for AWS CLI
if ! command -v aws &> /dev/null; then
  echo "AWS CLI not found! Please install AWS CLI."
  exit 1
fi

# Check AWS authentication
if ! AWS_PAGER= aws sts get-caller-identity --output text >/dev/null 2>&1; then
  echo "AWS CLI is not authenticated. Please run 'aws configure' or authenticate."
  exit 1
fi

# Check and create S3 bucket for Terraform state
BUCKET="microstack-terraform-aws-state"
REGION="eu-west-2"
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "S3 bucket $BUCKET does not exist. Creating..."
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null 2>&1 || true
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" --create-bucket-configuration LocationConstraint="$REGION" >/dev/null 2>&1 || true
  fi
else
  echo "S3 bucket $BUCKET exists."
fi

# Check for terraform and install if missing
if ! command -v terraform &> /dev/null; then
  echo "Terraform not found! Installing..."
  if command -v brew &> /dev/null; then
    brew tap hashicorp/tap
    brew install hashicorp/tap/terraform
  else
    echo "Please install terraform manually."; exit 1;
  fi
fi

# Parse argument for destroy
ACTION="apply"
if [[ "$1" == "destroy" ]]; then
  ACTION="destroy"
fi
 
if [[ "$ACTION" == "apply" ]]; then
  terraform_apply cloud-resources
  terraform_apply k3s-config
  update_hosts
else
  # Destroy mode
  # Longhorn NS cleanup
  kubectl delete ns longhorn-system --kubeconfig cloud-resources/k3s.yaml --wait=false || true
  kubectl get namespace longhorn-system --kubeconfig cloud-resources/k3s.yaml -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/longhorn-system/finalize" --kubeconfig cloud-resources/k3s.yaml -f - || true

  terraform_destroy k3s-config helm_release.longhorn

  terraform_destroy cloud-resources

  # Delete S3 bucket
  aws s3 rb s3://$BUCKET --force || true
fi
