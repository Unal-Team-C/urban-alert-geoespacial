#!/usr/bin/env bash
# Tests check-platform.sh with a fake `aws` on the PATH (no AWS credentials needed).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../check-platform.sh"
fake_bin="$(mktemp -d)"
trap 'rm -rf "$fake_bin"' EXIT

# The fake CLI prints $FAKE_MISSING as the InvalidParameters of `aws ssm get-parameters`.
cat >"$fake_bin/aws" <<'FAKE'
#!/usr/bin/env bash
[[ "$1 $2" == "ssm get-parameters" ]] || { echo "unexpected call: $*" >&2; exit 99; }
echo "${FAKE_MISSING:-}"
FAKE
chmod +x "$fake_bin/aws"

failures=0
check() {
  local name="$1" expected_code="$2" expected_text="$3" output code
  set +e
  output="$(PATH="$fake_bin:$PATH" bash "$script" 2>&1)"
  code=$?
  set -e
  if [[ "$code" == "$expected_code" && "$output" == *"$expected_text"* ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name (exit $code): $output"
    failures=$((failures + 1))
  fi
}

FAKE_MISSING="" check "all parameters present" 0 "Plataforma compartida disponible"
FAKE_MISSING="None" check "CLI prints None when nothing is missing" 0 "Plataforma compartida disponible"
FAKE_MISSING="/urban-alert/plataforma/api-id" check "one parameter missing" 1 "plataforma compartida no está aprovisionada"
FAKE_MISSING=$'/urban-alert/plataforma/vpc-id\t/urban-alert/plataforma/api-id' check "several missing are listed" 1 "/urban-alert/plataforma/vpc-id /urban-alert/plataforma/api-id"

exit "$failures"
