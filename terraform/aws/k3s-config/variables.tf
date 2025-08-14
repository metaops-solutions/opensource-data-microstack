variable "airbyte_namespace" {
  description = "Namespace for Airbyte deployment."
  type        = string
  default     = "airbyte"
}

variable "aws_region" {
  description = "AWS region for provider."
  type        = string
  default     = "eu-west-2"
}

variable "admin_email" {
  description = "Email address for the Authentik admin user."
  type        = string
  default     = "admin@metaops.solutions"
}

variable "airbyte_hostname" {
  description = "Hostname for Airbyte."
  type        = string
  default     = "airbyte.metaops.solutions.local"
}

variable "authentik_hostname" {
  description = "Hostname for Authentik."
  type        = string
  default     = "authentik.metaops.solutions.local"
}

variable "metabase_hostname" {
  description = "Hostname for Metabase."
  type        = string
  default     = "metabase.metaops.solutions.local"
}

variable "main_domain" {
  description = "Main domain for the platform."
  type        = string
  default     = "metaops.solutions.local"
}

variable "minio_storage_volume_claim_value" {
  description = "MinIO storage volume claim size for Airbyte."
  type        = string
  default     = "20Gi"
}

variable "authentik_storage_size" {
  description = "Storage size for Authentik."
  type        = string
  default     = "8Gi"
}

variable "longhorn_default_replica_count" {
  description = "Default replica count for Longhorn."
  type        = number
  default     = 2
}

variable "postgres_primary_persistence_size" {
  description = "Primary persistence size for Postgres."
  type        = string
  default     = "20Gi"
}