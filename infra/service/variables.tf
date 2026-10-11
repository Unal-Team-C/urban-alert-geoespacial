variable "region" {
  type = string
}

variable "state_bucket" {
  description = "Bucket holding the base stack state."
  type        = string
}

variable "image_tag" {
  description = "Image tag (commit SHA) to deploy."
  type        = string
}

variable "cpu" {
  description = "CPU units per task."
  type        = string
}

variable "memory" {
  description = "Memory per task, in MiB."
  type        = string
}

variable "container_port" {
  type = number
}

variable "health_check_path" {
  type = string
}

variable "min_tasks" {
  type = number
}

variable "max_tasks" {
  type = number
}

variable "cpu_target_percent" {
  type = number
}

variable "db_pool_min" {
  type = number
}

variable "db_pool_max" {
  description = "Connections per task. db_pool_max × max_tasks must stay within the 50-connection budget (plan D-015)."
  type        = number
}

variable "max_radius_m" {
  type = number
}
