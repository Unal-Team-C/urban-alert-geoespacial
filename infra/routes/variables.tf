variable "region" {
  type = string
}

variable "express_endpoint" {
  description = "Host of the Express service (output service_endpoint of infra/service), without scheme."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9.-]+$", var.express_endpoint))
    error_message = "express_endpoint must be a bare host name such as urban-alert-geoespacial-abc.ecs.us-east-2.on.aws (no scheme, no path)."
  }
}

variable "express_listener_arn" {
  description = "ARN of the 443 listener of the internal Express load balancer (scripts/buscar-listener-express.sh)."
  type        = string

  validation {
    condition     = startswith(var.express_listener_arn, "arn:aws:elasticloadbalancing:") && strcontains(var.express_listener_arn, ":listener/app/")
    error_message = "express_listener_arn must be the ARN of an Application Load Balancer listener."
  }
}
