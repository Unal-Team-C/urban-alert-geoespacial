# terraform test with mocked providers and a fake platform contract: no AWS credentials, no real resources.
mock_provider "aws" {}

override_data {
  target = data.aws_ssm_parameter.api_id
  values = { value = "api123" }
}

override_data {
  target = data.aws_ssm_parameter.vpc_link_id
  values = { value = "vpclink123" }
}

override_data {
  target = data.aws_ssm_parameter.api_endpoint
  values = { value = "https://api123.execute-api.us-east-2.amazonaws.com" }
}

variables {
  express_endpoint     = "urban-alert-geoespacial-abc.ecs.us-east-2.on.aws"
  express_listener_arn = "arn:aws:elasticloadbalancing:us-east-2:348364742283:listener/app/ecs-express-gateway-alb-x/0123/4567"
}

run "exactly_the_three_routes_of_rf020" {
  command = plan

  assert {
    condition = toset([for r in aws_apigatewayv2_route.this : r.route_key]) == toset([
      "GET /api/v1/geoespacial/reports",
      "GET /api/v1/geoespacial/coordinates/{id}",
      "POST /api/v1/geoespacial/coordinates",
    ])
    error_message = "Only the three routes of RF-020 may be registered (no $default, no /health)."
  }

  assert {
    condition     = alltrue([for r in aws_apigatewayv2_route.this : r.api_id == "api123"])
    error_message = "Routes must go to the shared gateway read from SSM."
  }
}

run "assign_is_internal_and_queries_are_public" {
  command = plan

  assert {
    condition     = aws_apigatewayv2_route.this["assign"].authorization_type == "AWS_IAM"
    error_message = "POST /coordinates must require AWS_IAM (signed by Reportes)."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["reports"].authorization_type == "NONE" && aws_apigatewayv2_route.this["coordinate"].authorization_type == "NONE"
    error_message = "The GET routes are public."
  }
}

run "integrations_reach_the_internal_express_alb" {
  command = plan

  assert {
    condition = alltrue([for i in aws_apigatewayv2_integration.this :
      i.integration_type == "HTTP_PROXY" && i.connection_type == "VPC_LINK" && i.connection_id == "vpclink123" &&
      i.payload_format_version == "1.0" && i.integration_uri == var.express_listener_arn
    ])
    error_message = "Every integration must be an HTTP proxy over the platform VPC link to the 443 listener, payload 1.0."
  }

  assert {
    condition = alltrue([for i in aws_apigatewayv2_integration.this :
      i.request_parameters["overwrite:header.host"] == var.express_endpoint && i.tls_config[0].server_name_to_verify == var.express_endpoint
    ])
    error_message = "Every integration must overwrite Host and verify TLS against the service endpoint (otherwise the ALB returns 404)."
  }

  assert {
    condition = (
      aws_apigatewayv2_integration.this["reports"].request_parameters["overwrite:path"] == "/api/v1/geospatial/reports" &&
      aws_apigatewayv2_integration.this["coordinate"].request_parameters["overwrite:path"] == "/api/v1/geospatial/coordinates/$request.path.id" &&
      aws_apigatewayv2_integration.this["assign"].request_parameters["overwrite:path"] == "/api/v1/geospatial/coordinates"
    )
    error_message = "Public paths must be rewritten to the service paths."
  }

  assert {
    condition     = aws_apigatewayv2_integration.this["assign"].integration_method == "POST" && aws_apigatewayv2_integration.this["reports"].integration_method == "GET"
    error_message = "Integration methods must match the routes."
  }
}

run "gateway_url_comes_from_the_platform" {
  command = plan

  assert {
    condition     = output.gateway_url == "https://api123.execute-api.us-east-2.amazonaws.com"
    error_message = "gateway_url must be the api-endpoint published by the platform."
  }
}

run "endpoint_with_scheme_is_rejected" {
  command = plan

  variables {
    express_endpoint = "https://urban-alert-geoespacial-abc.ecs.us-east-2.on.aws"
  }

  expect_failures = [var.express_endpoint]
}

run "non_listener_arn_is_rejected" {
  command = plan

  variables {
    express_listener_arn = "arn:aws:elasticloadbalancing:us-east-2:348364742283:loadbalancer/app/ecs-express-gateway-alb-x/0123"
  }

  expect_failures = [var.express_listener_arn]
}
