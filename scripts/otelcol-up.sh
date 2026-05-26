#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${ROOT_DIR}"

set -a
source "${ROOT_DIR}/versions.env"
if [[ -f "${ROOT_DIR}/.env" ]]; then
  source "${ROOT_DIR}/.env"
fi
set +a

STACK_NAME=${STACK_NAME:-otel}
STACK_NETWORK=${STACK_NETWORK:-${STACK_NAME}-net}
PROMETHEUS_CONTAINER=${PROMETHEUS_CONTAINER:-${STACK_NAME}-prometheus}
LOKI_CONTAINER=${LOKI_CONTAINER:-${STACK_NAME}-loki}
TEMPO_CONTAINER=${TEMPO_CONTAINER:-${STACK_NAME}-tempo}
PYROSCOPE_CONTAINER=${PYROSCOPE_CONTAINER:-${STACK_NAME}-pyroscope}
OTELCOL_CONTAINER=${OTELCOL_CONTAINER:-${STACK_NAME}-otelcol}
OTELCOL_CPUS=${OTELCOL_CPUS:-1}
OTELCOL_MEMORY=${OTELCOL_MEMORY:-1G}
OTELCOL_READY_TIMEOUT=${OTELCOL_READY_TIMEOUT:-30}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

ensure_container_system() {
  local status
  status=$(container system status 2>/dev/null | awk '$1 == "status" { print $2 }')
  if [[ "${status}" != "running" ]]; then
    container system start
  fi
}

ensure_network() {
  if [[ "$(container network inspect "${STACK_NETWORK}" 2>/dev/null)" == "[]" ]]; then
    container network create "${STACK_NETWORK}" >/dev/null
  fi
}

pull_image() {
  container image pull "${OTELCOL_IMAGE}"
}

wait_for_http() {
  local url=$1
  local attempts=${2:-30}
  local i

  for ((i = 1; i <= attempts; i++)); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

require_cmd container
require_cmd curl
require_cmd awk

for dependency in \
  "${PROMETHEUS_CONTAINER}" \
  "${LOKI_CONTAINER}" \
  "${TEMPO_CONTAINER}" \
  "${PYROSCOPE_CONTAINER}"; do
  if [[ "$(container inspect "${dependency}" 2>/dev/null)" == "[]" ]]; then
    echo "Collector rendering expects ${dependency} to exist." >&2
    echo "Start Prometheus, Loki, Tempo, and Pyroscope first." >&2
    exit 1
  fi
done

ensure_container_system
ensure_network
pull_image

"${ROOT_DIR}/scripts/render-configs.sh"

if [[ ! -f "${ROOT_DIR}/configs/rendered/otelcol-config.yaml" ]]; then
  echo "Missing rendered otelcol config" >&2
  exit 1
fi

if [[ "$(container inspect "${OTELCOL_CONTAINER}" 2>/dev/null)" != "[]" ]]; then
  echo "Removing existing container ${OTELCOL_CONTAINER}"
  container delete -f "${OTELCOL_CONTAINER}" >/dev/null
fi

container run -d \
  --name "${OTELCOL_CONTAINER}" \
  --network "${STACK_NETWORK}" \
  --cpus "${OTELCOL_CPUS}" \
  --memory "${OTELCOL_MEMORY}" \
  -p 4317:4317 \
  -p 4318:4318 \
  -p 13133:13133 \
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered,target=/rendered,readonly" \
  "${OTELCOL_IMAGE}" \
  --feature-gates=service.profilesSupport \
  --config=/rendered/otelcol-config.yaml

if ! wait_for_http "http://127.0.0.1:13133/ready" "${OTELCOL_READY_TIMEOUT}"; then
  echo "OpenTelemetry Collector failed to become ready" >&2
  container logs -n 200 "${OTELCOL_CONTAINER}" >&2 || true
  exit 1
fi

echo "OpenTelemetry Collector is up"
echo "Health: http://localhost:13133/ready"
echo "OTLP gRPC: localhost:4317"
echo "OTLP HTTP: http://localhost:4318"
