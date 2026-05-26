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
LOKI_CONTAINER=${LOKI_CONTAINER:-${STACK_NAME}-loki}
LOKI_VOLUME=${LOKI_VOLUME:-${STACK_NAME}-loki-data}
LOKI_CPUS=${LOKI_CPUS:-1}
LOKI_MEMORY=${LOKI_MEMORY:-1G}
LOKI_USER=${LOKI_USER:-0:0}
LOKI_READY_TIMEOUT=${LOKI_READY_TIMEOUT:-120}

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
  if ! container volume inspect "${LOKI_VOLUME}" >/dev/null 2>&1; then
    container volume create "${LOKI_VOLUME}" >/dev/null
  fi
}

pull_image() {
  container image pull "${LOKI_IMAGE}"
}

wait_for_http() {
  local url=$1
  local attempts=${2:-120}
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

if [[ "$(container inspect "${LOKI_CONTAINER}" 2>/dev/null)" != "[]" ]]; then
  echo "Removing existing container ${LOKI_CONTAINER}"
  container delete -f "${LOKI_CONTAINER}" >/dev/null
fi

container run -d \
  --name "${LOKI_CONTAINER}" \
  --user "${LOKI_USER}" \
  --network "${STACK_NETWORK}" \
  --cpus "${LOKI_CPUS}" \
  --memory "${LOKI_MEMORY}" \
  -p 3100:3100 \
  -v "${LOKI_VOLUME}:/data/loki" \
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered,target=/rendered,readonly" \
  "${LOKI_IMAGE}" \
  -config.file=/rendered/loki-config.yaml

if ! wait_for_http "http://127.0.0.1:3100/ready" "${LOKI_READY_TIMEOUT}"; then
  echo "Loki failed to become ready" >&2
  container logs -n 200 "${LOKI_CONTAINER}" >&2 || true
  exit 1
fi

echo "Loki is up: http://localhost:3100"

