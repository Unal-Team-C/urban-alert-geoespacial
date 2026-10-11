#!/usr/bin/env bash
# Tests buscar-listener-express.sh with a fake `aws` on the PATH (no AWS credentials needed).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../buscar-listener-express.sh"
fake_bin="$(mktemp -d)"
trap 'rm -rf "$fake_bin"' EXIT

# FAKE_TG: target group returned by describe-services ("None" = Express case, no loadBalancers).
# FAKE_RULE_HOST: host of the host-header rule on the internal listener of alb-b.
cat >"$fake_bin/aws" <<'FAKE'
#!/usr/bin/env bash
case "$1 $2" in
  "ecs describe-services") echo "${FAKE_TG:-None}" ;;
  "elbv2 describe-target-groups") echo "arn:lb/alb-tg" ;;
  "elbv2 describe-load-balancers") printf 'arn:lb/alb-a\tarn:lb/alb-b\n' ;;
  "elbv2 describe-listeners")
    case "$*" in
      *alb-tg*) echo "arn:listener/tg-443" ;;
      *alb-a*) echo "arn:listener/a-443" ;;
      *alb-b*) echo "arn:listener/b-443" ;;
    esac ;;
  "elbv2 describe-rules")
    if [[ "$*" == *b-443* ]]; then
      printf '{"Rules":[{"Conditions":[{"Field":"host-header","HostHeaderConfig":{"Values":["%s"]}}]},{"Conditions":[]}]}\n' "${FAKE_RULE_HOST:-}"
    else
      echo '{"Rules":[{"Conditions":[{"Field":"host-header","Values":["otro.ecs.us-east-2.on.aws"]}]}]}'
    fi ;;
  *) echo "unexpected call: $*" >&2; exit 99 ;;
esac
FAKE
chmod +x "$fake_bin/aws"

failures=0
check() {
  local name="$1" expected_code="$2" expected_text="$3" output code
  set +e
  output="$(PATH="$fake_bin:$PATH" LISTENER_ATTEMPTS=2 LISTENER_SLEEP=0 bash "$script" cl svc geo.ecs.us-east-2.on.aws 2>&1)"
  code=$?
  set -e
  if [[ "$code" == "$expected_code" && "$output" == *"$expected_text"* ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name (exit $code): $output"
    failures=$((failures + 1))
  fi
}

FAKE_TG="arn:tg/geo" check "platform path via target group" 0 "arn:listener/tg-443"
FAKE_TG="None" FAKE_RULE_HOST="geo.ecs.us-east-2.on.aws" check "Express: listener found by host-header rule" 0 "arn:listener/b-443"
FAKE_TG="None" FAKE_RULE_HOST="otro.ecs.us-east-2.on.aws" check "no rule for the endpoint fails" 1 "no internal load balancer has a 443 listener rule"

exit "$failures"
