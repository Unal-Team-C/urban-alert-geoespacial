# Routes of the Geoespacial service in the shared API Gateway (spec 002 RF-020, plan D-023). Same pattern as
# infra/ejemplo-consumidor of Unal-Team-C/urban-alert-plataforma, which its CI validates.
data "aws_ssm_parameter" "api_id" {
  name = "/urban-alert/plataforma/api-id"
}

data "aws_ssm_parameter" "vpc_link_id" {
  name = "/urban-alert/plataforma/vpc-link-id"
}

data "aws_ssm_parameter" "api_endpoint" {
  name = "/urban-alert/plataforma/api-endpoint"
}

locals {
  # The provider marks SSM values as sensitive; these IDs are not secrets.
  api_id      = nonsensitive(data.aws_ssm_parameter.api_id.value)
  vpc_link_id = nonsensitive(data.aws_ssm_parameter.vpc_link_id.value)

  # Public route -> path of the service. NONE = public; AWS_IAM = internal (only Reportes, signed with SigV4).
  routes = {
    reports = {
      route_key = "GET /api/v1/geoespacial/reports"
      method    = "GET"
      path      = "/api/v1/geospatial/reports"
      auth      = "NONE"
    }
    coordinate = {
      route_key = "GET /api/v1/geoespacial/coordinates/{id}"
      method    = "GET"
      path      = "/api/v1/geospatial/coordinates/$request.path.id"
      auth      = "NONE"
    }
    assign = {
      route_key = "POST /api/v1/geoespacial/coordinates"
      method    = "POST"
      path      = "/api/v1/geospatial/coordinates"
      auth      = "AWS_IAM"
    }
  }
}

# The Express load balancer routes by Host: without overwriting Host with the service endpoint the request
# matches no listener rule and returns 404 (platform guide §4, platform plan D-005).
resource "aws_apigatewayv2_integration" "this" {
  for_each = local.routes

  api_id                 = local.api_id
  integration_type       = "HTTP_PROXY"
  integration_method     = each.value.method
  integration_uri        = var.express_listener_arn
  connection_type        = "VPC_LINK"
  connection_id          = local.vpc_link_id
  payload_format_version = "1.0"

  tls_config {
    server_name_to_verify = var.express_endpoint
  }

  request_parameters = {
    "overwrite:header.host" = var.express_endpoint
    "overwrite:path"        = each.value.path
  }
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.routes

  api_id             = local.api_id
  route_key          = each.value.route_key
  authorization_type = each.value.auth
  target             = "integrations/${aws_apigatewayv2_integration.this[each.key].id}"
}
