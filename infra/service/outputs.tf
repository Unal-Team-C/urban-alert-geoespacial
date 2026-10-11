output "service_arn" {
  value = aws_ecs_express_gateway_service.this.service_arn
}

output "service_name" {
  value = aws_ecs_express_gateway_service.this.service_name
}

output "cluster_name" {
  value = local.base.cluster_name
}

# Host of the internal Express load balancer rule, without scheme or path: the gateway integrations send it as
# Host and verify TLS against it (stack infra/routes, platform guide §3). Not reachable from the internet.
output "service_endpoint" {
  description = "Host name of the Express service (e.g. urban-alert-geoespacial-abc.ecs.us-east-2.on.aws)."
  value = (
    length(aws_ecs_express_gateway_service.this.ingress_paths) > 0
    ? trimsuffix(trimprefix(trimprefix(aws_ecs_express_gateway_service.this.ingress_paths[0].endpoint, "https://"), "http://"), "/")
    : null
  )
}
