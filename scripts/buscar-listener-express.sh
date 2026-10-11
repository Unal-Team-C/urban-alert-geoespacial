#!/usr/bin/env bash
# Prints the ARN of the HTTPS (443) listener of the internal load balancer that ECS Express created for a
# service. Gateway integrations of that service point to this listener (platform guide §3).
# Neither aws_ecs_express_gateway_service nor DescribeExpressGatewayService exposes it.
#
# Based on Unal-Team-C/urban-alert-plataforma/scripts/buscar-listener-express.sh, which follows
# ECS service -> target group -> load balancer -> listener. In practice (2026-10-11) DescribeServices returns no
# loadBalancers for an Express service, so when that path is empty this script looks for the internal ALB
# listener 443 whose host-header rule matches the service endpoint (that rule is how Express routes to it).
#
# Usage: scripts/buscar-listener-express.sh <cluster> <service name or ARN> <service endpoint host>
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <cluster> <service name or ARN> <service endpoint host>" >&2
  exit 2
fi
cluster="$1"
service="$2"
endpoint="$3"
attempts="${LISTENER_ATTEMPTS:-12}"

fail() {
  echo "buscar-listener-express: $1" >&2
  exit 1
}

listener_443() {
  # The backticks are a JMESPath literal, not a shell expansion.
  # shellcheck disable=SC2016
  aws elbv2 describe-listeners --load-balancer-arn "$1" \
    --query 'Listeners[?Port==`443`].ListenerArn | [0]' --output text
}

# 1. Path documented by the platform: ECS service -> target group -> load balancer.
target_group="$(aws ecs describe-services --cluster "$cluster" --services "$service" \
  --query 'services[0].loadBalancers[0].targetGroupArn' --output text)"
if [[ -n "$target_group" && "$target_group" != "None" ]]; then
  load_balancer="$(aws elbv2 describe-target-groups --target-group-arns "$target_group" \
    --query 'TargetGroups[0].LoadBalancerArns[0]' --output text)"
  [[ -n "$load_balancer" && "$load_balancer" != "None" ]] || fail "target group $target_group is not attached to a load balancer"
  listener="$(listener_443 "$load_balancer")"
  [[ -n "$listener" && "$listener" != "None" ]] || fail "load balancer $load_balancer has no listener on port 443"
  echo "$listener"
  exit 0
fi

# 2. Fallback: the internal ALB whose 443 listener has a host-header rule for this endpoint.
#    Retries because Express may add the rule shortly after the service reports a steady state.
for attempt in $(seq 1 "$attempts"); do
  for load_balancer in $(aws elbv2 describe-load-balancers \
    --query "LoadBalancers[?Scheme=='internal' && Type=='application'].LoadBalancerArn" --output text); do
    listener="$(listener_443 "$load_balancer")"
    [[ -n "$listener" && "$listener" != "None" ]] || continue
    if aws elbv2 describe-rules --listener-arn "$listener" --output json |
      jq -e --arg host "$endpoint" \
        '[.Rules[].Conditions[]? | select(.Field == "host-header") | (.HostHeaderConfig.Values // .Values // [])[]] | index($host) != null' \
        >/dev/null; then
      echo "$listener"
      exit 0
    fi
  done
  echo "attempt $attempt: no internal listener 443 with a host-header rule for $endpoint yet" >&2
  sleep "${LISTENER_SLEEP:-10}"
done

fail "no internal load balancer has a 443 listener rule for host $endpoint (service $service, cluster $cluster)"
