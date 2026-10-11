#!/usr/bin/env bash
# Smoke test of the Geoespacial service through the shared API Gateway (spec 002 HU-6, RF-020; plan D-024).
# Usage: scripts/smoke-gateway-geoespacial.sh https://<api-id>.execute-api.<region>.amazonaws.com
# Exit 0 when every check passes. SMOKE_ATTEMPTS (default 30, every 10 s) bounds the wait of the first check. The signed POST (HU-6 criterion 4) is verified manually: the runner role
# must not have execute-api:Invoke.
set -euo pipefail

if [[ $# -ne 1 || "$1" != https://* ]]; then
  echo "usage: $0 https://<api-id>.execute-api.<region>.amazonaws.com" >&2
  exit 2
fi
base="${1%/}/api/v1/geoespacial"
body="$(mktemp)"
trap 'rm -f "$body"' EXIT
failures=0

request() { # method url [data] -> prints the status code, body in $body
  local method="$1" url="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -s -o "$body" -w '%{http_code}' --max-time 15 -X "$method" -H 'Content-Type: application/json' -d "$data" "$url" || true
  else
    curl -s -o "$body" -w '%{http_code}' --max-time 15 -X "$method" "$url" || true
  fi
}

# 1. Public nearby query: 200 with a JSON array. Retries for up to 5 min while the new routes and tasks settle.
code=""
for attempt in $(seq 1 "${SMOKE_ATTEMPTS:-30}"); do
  code="$(request GET "$base/reports?lat=4.6486&lon=-74.0628&radius=1000")"
  [[ "$code" == "200" ]] && break
  echo "attempt $attempt: GET reports returned ${code:-no answer}"
  sleep 10
done
if [[ "$code" == "200" ]] && jq -e 'type == "array"' "$body" >/dev/null 2>&1; then
  echo "ok   GET /reports -> 200 with a JSON array"
else
  echo "FAIL GET /reports -> ${code:-no answer}, expected 200 with a JSON array: $(head -c 300 "$body")"
  failures=$((failures + 1))
fi

# 2. Public lookup of an unknown coordinate: the service itself answers 404 with its error shape.
uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen | tr '[:upper:]' '[:lower:]')"
code="$(request GET "$base/coordinates/$uuid")"
if [[ "$code" == "404" ]] && jq -e '.code == 404' "$body" >/dev/null 2>&1; then
  echo "ok   GET /coordinates/{unknown} -> 404 from the service"
else
  echo "FAIL GET /coordinates/{unknown} -> ${code:-no answer}, expected the service's {\"code\":404}: $(head -c 300 "$body")"
  failures=$((failures + 1))
fi

# 3. The internal assignment route rejects unsigned requests at the gateway.
code="$(request POST "$base/coordinates" "{\"reportId\":\"$uuid\",\"coordinate\":{\"lat\":4.6512,\"lon\":-74.0561}}")"
if [[ "$code" == "403" ]]; then
  echo "ok   unsigned POST /coordinates -> 403"
else
  echo "FAIL unsigned POST /coordinates -> ${code:-no answer}, expected 403"
  failures=$((failures + 1))
fi

# 4. Routes the service does not publish stay unregistered.
code="$(request GET "$base/health")"
if [[ "$code" == "404" ]]; then
  echo "ok   GET /health is not published (404)"
else
  echo "FAIL GET /health -> ${code:-no answer}, expected 404"
  failures=$((failures + 1))
fi

exit "$failures"
