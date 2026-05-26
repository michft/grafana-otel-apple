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
TEMPO_CONTAINER=${TEMPO_CONTAINER:-${STACK_NAME}-tempo}
TEMPO_VOLUME=${TEMPO_VOLUME:-${STACK_NAME}-tempo-data}
TEMPO_CPUS=${TEMPO_CPUS:-1}
TEMPO_MEMORY=${TEMPO_MEMORY:-1G}
TEMPO_USER=${TEMPO_USER:-0:0}
TEMPO_READY_TIMEOUT=${TEMPO_READY_TIMEOUT:-30}

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
  if ! container volume inspect "${TEMPO_VOLUME}" >/dev/null 2>&1; then
    container volume create "${TEMPO_VOLUME}" >/dev/null
  fi
}

pull_image() {
  container image pull "${TEMPO_IMAGE}"
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

if [[ "$(container inspect "${PROMETHEUS_CONTAINER}" 2>/dev/null)" == "[]" ]]; then
  echo "Tempo rendering currently expects ${PROMETHEUS_CONTAINER} to exist for remote_write config." >&2
  echo "Start Prometheus first with scripts/prometheus-up.sh" >&2
  exit 1
fi

ensure_container_system
ensure_network
ensure_volume
pull_image

"${ROOT_DIR}/scripts/render-configs.sh"

if [[ ! -f "${ROOT_DIR}/configs/rendered/tempo-config.yaml" ]]; then
  echo "Missing rendered tempo config" >&2
  exit 1
fi

if [[ "$(container inspect "${TEMPO_CONTAINER}" 2>/dev/null)" != "[]" ]]; then
  echo "Removing existing container ${TEMPO_CONTAINER}"
  container delete -f "${TEMPO_CONTAINER}" >/dev/null
fi

container run -d \
  --name "${TEMPO_CONTAINER}" \
  --user "${TEMPO_USER}" \
  --network "${STACK_NETWORK}" \
  --cpus "${TEMPO_CPUS}" \
  --memory "${TEMPO_MEMORY}" \
  -p 3200:3200 \
  -v "${TEMPO_VOLUME}:/data/tempo" \
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered,target=/rendered,readonly" \
  "${TEMPO_IMAGE}" \
  -config.file=/rendered/tempo-config.yaml

if ! wait_for_http "http://127.0.0.1:3200/ready" "${TEMPO_READY_TIMEOUT}"; then
  echo "Tempo failed to become ready" >&2
  container logs -n 200 "${TEMPO_CONTAINER}" >&2 || true
  exit 1
fi

echo "Tempo is up: http://localhost:3200"

