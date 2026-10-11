#!/usr/bin/env bash
# Runs the one-off schema task (python -m app.db.migrate) inside the VPC and fails if it fails.
# Spec 002 RF-016, plan D-003. Called by .github/workflows/provision.yml after the image is pushed.
#
# Required environment (from `terraform -chdir=infra/base output`):
#   CLUSTER, TASK_DEFINITION, SUBNETS (comma-separated), SECURITY_GROUP, LOG_GROUP, CONTAINER
# Optional: AWS_REGION (the AWS CLI reads it).
set -euo pipefail

: "${CLUSTER:?}" "${TASK_DEFINITION:?}" "${SUBNETS:?}" "${SECURITY_GROUP:?}" "${LOG_GROUP:?}" "${CONTAINER:?}"

network="awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SECURITY_GROUP}],assignPublicIp=ENABLED}"

echo "Starting schema task ${TASK_DEFINITION} in cluster ${CLUSTER}"
run_output=$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --task-definition "$TASK_DEFINITION" \
  --launch-type FARGATE \
  --network-configuration "$network" \
  --started-by "schema-migration" \
  --output json)

task_arn=$(jq -r '.tasks[0].taskArn // empty' <<<"$run_output")
if [[ -z "$task_arn" ]]; then
  echo "::error::The schema task did not start: $(jq -c '.failures' <<<"$run_output")"
  exit 1
fi
echo "Task: ${task_arn}"

# Default waiter: up to 100 checks every 6 s (10 min).
aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$task_arn"

task=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$task_arn" --output json)
exit_code=$(jq -r --arg c "$CONTAINER" '.tasks[0].containers[] | select(.name == $c) | .exitCode // empty' <<<"$task")
stopped_reason=$(jq -r '.tasks[0].stoppedReason // ""' <<<"$task")

echo "----- schema task logs -----"
task_id=${task_arn##*/}
aws logs get-log-events \
  --log-group-name "$LOG_GROUP" \
  --log-stream-name "${CONTAINER}/${CONTAINER}/${task_id}" \
  --start-from-head \
  --query 'events[].message' \
  --output text | tr '\t' '\n' || echo "(no logs: the container may not have started)"
echo "----------------------------"

if [[ -z "$exit_code" ]]; then
  echo "::error::The schema container did not run: ${stopped_reason}"
  exit 1
fi
if [[ "$exit_code" != "0" ]]; then
  echo "::error::Schema migration failed with exit code ${exit_code}"
  exit "$exit_code"
fi
echo "Schema applied."
