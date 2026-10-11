#!/usr/bin/env bash
# Prints the ARN of the HTTPS (443) listener of the internal load balancer that ECS Express created
# for a service. Gateway integrations of that service point to this listener (spec RF-006, plan D-005).
# Neither aws_ecs_express_gateway_service nor DescribeExpressGatewayService exposes it (research R-1),
# so it follows: ECS service -> target group -> load balancer -> listener 443.
# Usage: scripts/buscar-listener-express.sh <cluster> <service name or ARN>
# Copied unchanged from Unal-Team-C/urban-alert-plataforma (docs/integracion.md §3); run it after the service is deployed.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <cluster> <service name or ARN>" >&2
  exit 2
fi
cluster="$1"
service="$2"

fail() {
  echo "buscar-listener-express: $1" >&2
  exit 1
}

target_group="$(aws ecs describe-services --cluster "$cluster" --services "$service" \
  --query 'services[0].loadBalancers[0].targetGroupArn' --output text)"
[[ -n "$target_group" && "$target_group" != "None" ]] ||
  fail "service $service in cluster $cluster has no load balancer target group (is it an Express service that finished deploying?)"

load_balancer="$(aws elbv2 describe-target-groups --target-group-arns "$target_group" \
  --query 'TargetGroups[0].LoadBalancerArns[0]' --output text)"
[[ -n "$load_balancer" && "$load_balancer" != "None" ]] ||
  fail "target group $target_group is not attached to a load balancer"

# The backticks are a JMESPath literal, not a shell expansion.
# shellcheck disable=SC2016
listener="$(aws elbv2 describe-listeners --load-balancer-arn "$load_balancer" \
  --query 'Listeners[?Port==`443`].ListenerArn | [0]' --output text)"
[[ -n "$listener" && "$listener" != "None" ]] ||
  fail "load balancer $load_balancer has no listener on port 443"

echo "$listener"
