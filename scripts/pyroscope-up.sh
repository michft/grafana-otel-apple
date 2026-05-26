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
PYROSCOPE_CONTAINER=${PYROSCOPE_CONTAINER:-${STACK_NAME}-pyroscope}
PYROSCOPE_VOLUME=${PYROSCOPE_VOLUME:-${STACK_NAME}-pyroscope-data}
PYROSCOPE_CPUS=${PYROSCOPE_CPUS:-1}
PYROSCOPE_MEMORY=${PYROSCOPE_MEMORY:-1G}
PYROSCOPE_USER=${PYROSCOPE_USER:-0:0}
PYROSCOPE_READY_TIMEOUT=${PYROSCOPE_READY_TIMEOUT:-120}

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
  if ! container volume inspect "${PYROSCOPE_VOLUME}" >/dev/null 2>&1; then
    container volume create "${PYROSCOPE_VOLUME}" >/dev/null
  fi
}

pull_image() {
  container image pull "${PYROSCOPE_IMAGE}"
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

if [[ ! -f "${ROOT_DIR}/configs/rendered/pyroscope-config.yaml" ]]; then
  echo "Missing rendered pyroscope config" >&2
  exit 1
fi

if [[ "$(container inspect "${PYROSCOPE_CONTAINER}" 2>/dev/null)" != "[]" ]]; then
  echo "Removing existing container ${PYROSCOPE_CONTAINER}"
  container delete -f "${PYROSCOPE_CONTAINER}" >/dev/null
fi

container run -d \
  --name "${PYROSCOPE_CONTAINER}" \
  --user "${PYROSCOPE_USER}" \
  --network "${STACK_NETWORK}" \
  --cpus "${PYROSCOPE_CPUS}" \
  --memory "${PYROSCOPE_MEMORY}" \
  -p 4040:4040 \
  -v "${PYROSCOPE_VOLUME}:/data/pyroscope" \
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered,target=/rendered,readonly" \
  "${PYROSCOPE_IMAGE}" \
  server \
  -config.file=/rendered/pyroscope-config.yaml

if ! wait_for_http "http://127.0.0.1:4040/ready" "${PYROSCOPE_READY_TIMEOUT}"; then
  echo "Pyroscope failed to become ready" >&2
  container logs -n 200 "${PYROSCOPE_CONTAINER}" >&2 || true
  exit 1
fi

echo "Pyroscope is up: http://localhost:4040"
