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

GRAFANA_VOLUME=${GRAFANA_VOLUME:-${STACK_NAME}-grafana-data}
PROMETHEUS_VOLUME=${PROMETHEUS_VOLUME:-${STACK_NAME}-prometheus-data}
LOKI_VOLUME=${LOKI_VOLUME:-${STACK_NAME}-loki-data}
TEMPO_VOLUME=${TEMPO_VOLUME:-${STACK_NAME}-tempo-data}
PYROSCOPE_VOLUME=${PYROSCOPE_VOLUME:-${STACK_NAME}-pyroscope-data}

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
    echo "Starting Apple container services"
    container system start
  fi
}

network_exists() {
  [[ "$(container network inspect "$1" 2>/dev/null)" != "[]" ]]
}

ensure_network() {
  if ! network_exists "${STACK_NETWORK}"; then
    echo "Creating network ${STACK_NETWORK}"
    container network create "${STACK_NETWORK}" >/dev/null
  fi
}

ensure_volume() {
  local volume_name=$1
  if ! container volume inspect "${volume_name}" >/dev/null 2>&1; then
    echo "Creating volume ${volume_name}"
    container volume create "${volume_name}" >/dev/null
  fi
}

pull_image() {
  local image_ref=$1
  echo "Pulling ${image_ref}"
  container image pull "${image_ref}"
}

require_cmd container
require_cmd awk

ensure_container_system
ensure_network

for volume_name in \
  "${GRAFANA_VOLUME}" \
  "${PROMETHEUS_VOLUME}" \
  "${LOKI_VOLUME}" \
  "${TEMPO_VOLUME}" \
  "${PYROSCOPE_VOLUME}"; do
  ensure_volume "${volume_name}"
done

for image_ref in \
  "${PROMETHEUS_IMAGE}" \
  "${LOKI_IMAGE}" \
  "${TEMPO_IMAGE}" \
  "${PYROSCOPE_IMAGE}" \
  "${GRAFANA_IMAGE}" \
  "${OTELCOL_IMAGE}"; do
  pull_image "${image_ref}"
done

echo "Bootstrap complete"
