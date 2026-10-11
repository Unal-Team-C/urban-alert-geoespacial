output "service_arn" {
  value = aws_ecs_express_gateway_service.this.service_arn
}

output "service_url" {
  description = "Public HTTPS URL of the service."
  value = (
    length(aws_ecs_express_gateway_service.this.ingress_paths) > 0
    ? (startswith(aws_ecs_express_gateway_service.this.ingress_paths[0].endpoint, "http")
      ? aws_ecs_express_gateway_service.this.ingress_paths[0].endpoint
    : "https://${aws_ecs_express_gateway_service.this.ingress_paths[0].endpoint}")
    : null
  )
}
