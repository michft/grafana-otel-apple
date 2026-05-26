#!/usr/bin/env bash

set -euo pipefail

check_http() {
  local label=$1
  local url=$2

  echo "Checking ${label}: ${url}"
  curl -fsS "${url}" >/dev/null
}

check_http "Grafana health" "http://127.0.0.1:3000/api/health"
check_http "Prometheus runtime info" "http://127.0.0.1:9090/api/v1/status/runtimeinfo"
check_http "Tempo ready" "http://127.0.0.1:3200/ready"
check_http "Pyroscope ready" "http://127.0.0.1:4040/ready"
check_http "Collector ready" "http://127.0.0.1:13133/ready"

otel_status=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:4318/v1/traces || true)
if [[ "${otel_status}" == "000" ]]; then
  echo "OTLP HTTP endpoint is not reachable" >&2
  exit 1
fi

echo "Smoke test passed"
