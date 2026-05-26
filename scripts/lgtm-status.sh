#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

set -a
source "${ROOT_DIR}/versions.env"
if [[ -f "${ROOT_DIR}/.env" ]]; then
  source "${ROOT_DIR}/.env"
fi
set +a

STACK_NAME=${STACK_NAME:-otel}
STACK_NETWORK=${STACK_NETWORK:-${STACK_NAME}-net}

echo "Network: ${STACK_NETWORK}"
echo "Containers:"

for name in \
  "${PROMETHEUS_CONTAINER:-${STACK_NAME}-prometheus}" \
  "${LOKI_CONTAINER:-${STACK_NAME}-loki}" \
  "${TEMPO_CONTAINER:-${STACK_NAME}-tempo}" \
  "${PYROSCOPE_CONTAINER:-${STACK_NAME}-pyroscope}" \
  "${GRAFANA_CONTAINER:-${STACK_NAME}-grafana}" \
  "${OTELCOL_CONTAINER:-${STACK_NAME}-otelcol}"; do
  if [[ "$(container inspect "${name}" 2>/dev/null)" != "[]" ]]; then
    state=$(container inspect "${name}" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "  ${name}: ${state}"
  else
    echo "  ${name}: missing"
  fi
done

echo "URLs:"
echo "  Grafana: http://localhost:3000"
echo "  OTLP HTTP: http://localhost:4318"
echo "  Prometheus: http://localhost:9090"
echo "  Tempo: http://localhost:3200"
echo "  Pyroscope: http://localhost:4040"
