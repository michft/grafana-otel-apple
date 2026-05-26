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
PROMETHEUS_VOLUME=${PROMETHEUS_VOLUME:-${STACK_NAME}-prometheus-data}
PROMETHEUS_CPUS=${PROMETHEUS_CPUS:-1}
PROMETHEUS_MEMORY=${PROMETHEUS_MEMORY:-1G}
PROMETHEUS_USER=${PROMETHEUS_USER:-0:0}

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

ensure_volume() {
  if ! container volume inspect "${PROMETHEUS_VOLUME}" >/dev/null 2>&1; then
    container volume create "${PROMETHEUS_VOLUME}" >/dev/null
  fi
}

pull_image() {
  container image pull "${PROMETHEUS_IMAGE}"
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

ensure_container_system
ensure_network
ensure_volume
pull_image

"${ROOT_DIR}/scripts/render-configs.sh"

if [[ "$(container inspect "${PROMETHEUS_CONTAINER}" 2>/dev/null)" != "[]" ]]; then
  echo "Removing existing container ${PROMETHEUS_CONTAINER}"
  container delete -f "${PROMETHEUS_CONTAINER}" >/dev/null
fi

container run -d \
  --name "${PROMETHEUS_CONTAINER}" \
  --user "${PROMETHEUS_USER}" \
  --network "${STACK_NETWORK}" \
  --cpus "${PROMETHEUS_CPUS}" \
  --memory "${PROMETHEUS_MEMORY}" \
  -p 9090:9090 \
  -v "${PROMETHEUS_VOLUME}:/prometheus" \
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered,target=/rendered,readonly" \
  "${PROMETHEUS_IMAGE}" \
  --web.enable-remote-write-receiver \
  --web.enable-otlp-receiver \
  --enable-feature=exemplar-storage \
  --storage.tsdb.path=/prometheus \
  --config.file=/rendered/prometheus.yaml

if ! wait_for_http "http://127.0.0.1:9090/api/v1/status/runtimeinfo"; then
  echo "Prometheus failed to become ready" >&2
  container logs -n 200 "${PROMETHEUS_CONTAINER}" >&2 || true
  exit 1
fi

echo "Prometheus is up: http://localhost:9090"
