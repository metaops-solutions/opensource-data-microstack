## Additional Information
# Local Setup Guide

This guide explains how to set up your local development environment using the provided `setup.sh` script.

## What Gets Installed

| Service      | Purpose                                                      |
|------------- |--------------------------------------------------------------|
| K3d          | Lightweight Kubernetes cluster in Docker                     |
| Traefik      | Ingress controller for routing traffic                       |
| Cert-Manager | TLS certificate management                                   |
| Postgres     | Database with preconfigured users and databases              |
| Airbyte      | Data integration platform                                    |
| Metabase     | Analytics and dashboarding                                   |
| Authentik    | Authentication and identity provider                         |

## How to Use the Script

1. **Install prerequisites**
   - Homebrew (macOS)
   - Docker (ensure Docker Desktop is installed and the VM is configured with at least 8GB RAM)
   - Sudo access is required for modifying `/etc/hosts` and some setup steps

2. **Configure environment**
   - Copy `.env.example` to `.env` and fill in required values.

3. **Run the setup**
   ```bash
   ./setup.sh
   ```
   - This will create the k3d cluster, install all services, and configure everything automatically.

4. **Delete the cluster**
   ```bash
   ./setup.sh delete-only
   ```
   - Deletes the k3d cluster, cleans up data, and removes the local CA from your keychain.

5. **Recreate the cluster**
   ```bash
   ./setup.sh recreate
   ```
   - Deletes and then recreates the cluster and all resources.

## Accessing Services
- Hostnames for all services are added to `/etc/hosts` and resolve to `127.0.0.1`.
- Example URLs:
  - Airbyte: `https://airbyte.metaops.solutions.local`
  - Metabase: `https://metabase.metaops.solutions.local`
  - Authentik: `https://authentik.metaops.solutions.local`

## Database Setup
- **Postgres** is installed with the following users and databases:
  - `airbyte` user and database
  - `authentik` user and database
  - `metabase` user and database
- Passwords and connection details are set via `.env`.
- Each user is granted the necessary privileges for their application.


## Authentik Setup & Airbyte Authentication

- **Authentik** is deployed as an authentication and identity provider for your local stack.
- It is integrated with Traefik as a forward authentication middleware.
- **Airbyte** is fronted by Authentik, meaning all access to Airbyte's web UI is authenticated via Authentik SSO.
- The integration is managed by Traefik middleware and ingress configuration, ensuring secure access to Airbyte.
- You can configure Authentik users, groups, and policies for fine-grained access control.

### Accessing Airbyte

To log in to the Airbyte web UI, use the following credentials:

- **URL:** https://airbyte.metaops.solutions.local (or the value of `AIRBYTE_HOST` in your `.env`)
- **Username:** The value of `AUTHENTIK_ADMIN_EMAIL` in your `.env` (default: `admin@metaops.solutions`)
- **Password:** The value of `AUTHENTIK_BOOTSTRAP_PASSWORD` in your `.env`

These credentials are set during setup and can be changed in your `.env` file before running the script.

## TLS/CA Trust
- A self-signed local CA is generated and used by cert-manager to issue certificates for all services.
- The CA is not added to your system keychain; it is only used internally for service certificates.

## Additional info
- All manifests use environment variable substitution for easy configuration.
- The setup is idempotent and safe to rerun.
- For troubleshooting, check the output of `setup.sh` and the logs of individual services.

---
For more details, see comments in `setup.sh` and the individual manifest files.

