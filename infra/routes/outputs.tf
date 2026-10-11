output "gateway_url" {
  description = "Public URL of the shared gateway; the service lives under /api/v1/geoespacial/."
  value       = nonsensitive(data.aws_ssm_parameter.api_endpoint.value)
}

output "route_keys" {
  value = sort([for r in aws_apigatewayv2_route.this : r.route_key])
}
