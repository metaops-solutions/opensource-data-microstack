# Terraform AWS Setup

This directory contains Terraform configurations for provisioning AWS resources and deploying services for the microstack project.

## Deployed Services

| Service    | Purpose                                                                 |
|------------|-------------------------------------------------------------------------|
| Airbyte    | Data integration and ELT platform for moving and transforming data      |
| Metabase   | Analytics and dashboarding for exploring and visualizing data           |
| Authentik  | Authentication and identity provider for secure access and SSO          |
| Postgres   | Relational database for storing application data                        |
| Longhorn   | Distributed block storage for Kubernetes persistent volumes (PVCs)      |
| Cert-Manager | Automated management of SSL/TLS certificates in Kubernetes            |
| Traefik    | Ingress controller for routing external traffic to services             |
| K3s        | Lightweight Kubernetes distribution for running containerized workloads |

## Structure

- `cloud-resources/`: Core AWS infrastructure (VPC, EC2, DISK, etc.)
- `k3s-config/`: Kubernetes (K3s) cluster and service deployments (Airbyte, Authentik, Cert-Manager, Longhorn, Metabase, Postgres)

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0 installed
- Access to AWS account with required permissions

## Usage

The main entry point for deploying infrastructure is the `setup.sh` script. This script installs required tools and then runs Terraform to set up the environment, automating initialization, planning, and applying the configuration for AWS resources.

### Run Setup
```sh
./setup.sh
```

This will:
- Initialize Terraform
- Plan the infrastructure changes
- Apply the configuration

## Secrets & Passwords

Terraform will create and manage the following secrets in AWS Secrets Manager. These secrets are used by various services and components deployed in the stack. Note: the actual secret names will have a random suffix appended (e.g., `opensource-data-microstack-airbyte-db-password-xxxxxx`).

| Secret Name (prefix)                                     | Usage                                                      |
|----------------------------------------------------------|------------------------------------------------------------|
| opensource-data-microstack-airbyte-db-password           | Airbyte DB password for service connections                |
| opensource-data-microstack-authentik-bootstrap           | Authentik bootstrap password and token for initial setup   |
| opensource-data-microstack-authentik-postgres-password   | Authentik Postgres DB password                             |
| opensource-data-microstack-metabase-db-password          | Metabase DB password for service connections               |
| opensource-data-microstack-k3s-ssh-private-key           | SSH private key for K3s node access                        |
| opensource-data-microstack-k3s-kubeconfig                | K3s cluster kubeconfig file for kubectl access             |

### Retrieving Secrets
After deployment, list secrets to get the full name with suffix:
```sh
aws secretsmanager list-secrets --query "SecretList[?contains(Name, '<secret-prefix>')].Name" --output text
```
Replace `<secret-prefix>` with the prefix from the table above.

Then retrieve the secret value:
```sh
aws secretsmanager get-secret-value --secret-id <full-secret-name>
```
Replace `<full-secret-name>` with the actual name returned above. Refer to Terraform outputs for actual values and usage in your services.

## Longhorn: Persistent Volume Management

- **Longhorn** is used to manage persistent volumes (PVCs) for Kubernetes workloads.
- It utilizes extra disks attached to EC2 instances for storage.
- Storage can be expanded easily by adding more disks and updating the Longhorn configuration.
  
To expand storage:
- Add new disk objects to the `data_disks` variable in `cloud-resources/variables.tf`.
- Run `./setup.sh` again.

The script will automatically create and attach the new disks, add them to LVM, and expand the filesystem. Longhorn will detect the additional storage and make it available for PVCs.

## Customization

You can customize your deployment by adjusting variables in `variables.tf`:
- EC2 instance type (SKU)
- Hostnames for services
- Disk sizes and number of disks
- PVC (Persistent Volume Claim) storage size for workloads
- AWS region and networking parameters
Refer to comments in `variables.tf` for details on each variable.


## Connecting to the Cluster

After setup, a `k3s.yaml` Kubernetes config file will be created under `cloud-resources/`. This file allows you to connect to the cluster using kubectl or k9s:

```sh
kubectl get ns --kubeconfig ./cloud-resources/k3s.yaml
k9s --kubeconfig ./cloud-resources/k3s.yaml
```
Make sure `kubectl` and `k9s` are installed on your system.

The same kubeconfig is also stored in AWS Secrets Manager as a secret (`opensource-data-microstack-k3s-kubeconfig`).

For SSH access, connect to the EC2 instance using its public IP. The SSH private key is stored in AWS Secrets Manager (`opensource-data-microstack-k3s-ssh-private-key`).

## IP Whitelist / NSG Rules

By default, the IP address where you run the setup script will be whitelisted to access the Kubernetes API, ports 80/443, and SSH. To allow additional IPs, update the `ssh_whitelist_cidrs` variable in `variables.tf`.

## Accessing Services Deployed on K3s

Host entries for the following services are added to `/etc/hosts`:
- `https://airbyte.metaops.solutions.local`
- `https://metabase.metaops.solutions.local`
- `https://authentik.metaops.solutions.local`

If you change hostnames in `variables.tf`, update your `/etc/hosts` file accordingly.

SSL certificates for these services are self-signed and issued by cert-manager running on the cluster. When accessing from a browser, you may need to accept and continue past SSL warnings.

## Airbyte authentication 

To log in to Airbyte, use the credentials managed by Authentik:

- **Username:** `admin@metaops.solutions` (unless you have changed the `admin_email` variable in Terraform)
-- **Password:** Retrieve from AWS Secrets Manager. Note: the actual secret name will have a random suffix appended (e.g., `opensource-data-microstack-authentik-bootstrap-xxxxxx`).

Refer to the [Secrets & Passwords](#secrets--passwords) section above for instructions on retrieving the password from AWS Secrets Manager. Use these credentials to authenticate via the Authentic web UI.

## Destroy 

To delete all resources created by Terraform, run:
```sh
./setup.sh destroy
```

---
For more details, refer to individual service configs and comments in `.tf` files.
