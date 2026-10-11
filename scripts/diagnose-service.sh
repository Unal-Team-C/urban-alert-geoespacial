#!/usr/bin/env bash
# Prints why an ECS Express deployment failed: service events, stopped tasks with their reasons and the last
# service logs. Run by provision.yml when the service step fails. Never fails itself.
# Usage: scripts/diagnose-service.sh <cluster> <service> <log group>
set -uo pipefail

cluster="$1"
service="$2"
log_group="$3"

echo "===== Service events (latest first) ====="
aws ecs describe-services --cluster "$cluster" --services "$service" \
  --query 'services[0].events[:15].[createdAt,message]' --output text || true

echo "===== Deployments ====="
aws ecs describe-services --cluster "$cluster" --services "$service" \
  --query 'services[0].deployments[].[status,rolloutState,rolloutStateReason,runningCount,failedTasks]' --output text || true

echo "===== Stopped tasks ====="
tasks=$(aws ecs list-tasks --cluster "$cluster" --service-name "$service" --desired-status STOPPED \
  --query 'taskArns[:5]' --output text 2>/dev/null || true)
if [[ -n "$tasks" && "$tasks" != "None" ]]; then
  # shellcheck disable=SC2086 # several task ARNs, split on purpose
  aws ecs describe-tasks --cluster "$cluster" --tasks $tasks \
    --query 'tasks[].{stopped:stoppedReason,code:stopCode,containers:containers[].{name:name,exit:exitCode,reason:reason}}' \
    --output json || true
else
  echo "(none)"
fi

echo "===== Last service logs ====="
aws logs filter-log-events --log-group-name "$log_group" --limit 40 \
  --query 'events[].message' --output text 2>/dev/null | tr '\t' '\n' | tail -40 || echo "(no logs)"
exit 0
