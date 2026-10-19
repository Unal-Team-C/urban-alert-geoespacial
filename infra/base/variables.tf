variable "region" {
  description = "AWS region."
  type        = string
}

variable "name" {
  description = "Prefix for every resource of this service. Must start with urban-alert- (IAM policies of the pipeline are scoped to it)."
  type        = string

  validation {
    condition     = startswith(var.name, "urban-alert-")
    error_message = "name must start with \"urban-alert-\"."
  }
}

variable "image_tag" {
  description = "Image tag (commit SHA) used by the schema task definition."
  type        = string
}

variable "allow_destroy" {
  description = "Only the deprovision workflow sets it: disables RDS deletion protection and lets ECR be deleted with its images."
  type        = bool
  default     = false
}

variable "final_snapshot_suffix" {
  description = "Suffix of the final RDS snapshot taken on destroy (the deprovision workflow passes its run id)."
  type        = string
  default     = "manual"
}

variable "db_name" {
  description = "Database created in the RDS instance."
  type        = string
}

variable "db_app_user" {
  description = "Login role used by the service (SELECT, INSERT on coordinates only)."
  type        = string
}

variable "db_engine_version" {
  description = "PostgreSQL major version."
  type        = string
}

variable "db_instance_class" {
  type = string
}

variable "db_allocated_storage_gb" {
  type = number
}

variable "db_max_allocated_storage_gb" {
  type = number
}

variable "db_backup_retention_days" {
  type = number

  validation {
    condition     = var.db_backup_retention_days >= 7
    error_message = "Backups must be kept at least 7 days (RNF-007)."
  }
}

variable "ecr_keep_images" {
  description = "Number of images kept in ECR."
  type        = number
}

variable "log_retention_days" {
  type = number
}

variable "schema_task_cpu" {
  type = number
}

variable "schema_task_memory" {
  type = number
}

variable "container_port" {
  description = "Port the service container listens on (must match infra/service)."
  type        = number
  default     = 8000
}
