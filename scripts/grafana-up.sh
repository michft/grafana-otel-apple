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
GRAFANA_CONTAINER=${GRAFANA_CONTAINER:-${STACK_NAME}-grafana}
GRAFANA_VOLUME=${GRAFANA_VOLUME:-${STACK_NAME}-grafana-data}
GRAFANA_CPUS=${GRAFANA_CPUS:-1}
GRAFANA_MEMORY=${GRAFANA_MEMORY:-1G}
GRAFANA_USER=${GRAFANA_USER:-0:0}
GRAFANA_READY_TIMEOUT=${GRAFANA_READY_TIMEOUT:-30}

GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}
GF_AUTH_ANONYMOUS_ENABLED=${GF_AUTH_ANONYMOUS_ENABLED:-true}
GF_AUTH_ANONYMOUS_ORG_ROLE=${GF_AUTH_ANONYMOUS_ORG_ROLE:-Admin}
GF_PLUGINS_PREINSTALL=${GF_PLUGINS_PREINSTALL:-grafana-pyroscope-app,grafana-llm-app}

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
  if ! container volume inspect "${GRAFANA_VOLUME}" >/dev/null 2>&1; then
    container volume create "${GRAFANA_VOLUME}" >/dev/null
  fi
}

pull_image() {
  container image pull "${GRAFANA_IMAGE}"
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
    echo "Grafana rendering expects ${dependency} to exist." >&2
    echo "Start Prometheus, Loki, Tempo, and Pyroscope first." >&2
    exit 1
  fi
done

ensure_container_system
ensure_network
ensure_volume
pull_image

"${ROOT_DIR}/scripts/render-configs.sh"

if [[ ! -d "${ROOT_DIR}/configs/rendered/grafana-provisioning" ]]; then
  echo "Missing rendered Grafana provisioning directory" >&2
  exit 1
fi

if [[ "$(container inspect "${GRAFANA_CONTAINER}" 2>/dev/null)" != "[]" ]]; then
  echo "Removing existing container ${GRAFANA_CONTAINER}"
  container delete -f "${GRAFANA_CONTAINER}" >/dev/null
fi

container run -d \
  --name "${GRAFANA_CONTAINER}" \
  --user "${GRAFANA_USER}" \
  --network "${STACK_NETWORK}" \
  --cpus "${GRAFANA_CPUS}" \
  --memory "${GRAFANA_MEMORY}" \
  -p 3000:3000 \
  -e "GF_SECURITY_ADMIN_USER=${GRAFANA_ADMIN_USER}" \
  -e "GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}" \
  -e "GF_AUTH_ANONYMOUS_ENABLED=${GF_AUTH_ANONYMOUS_ENABLED}" \
  -e "GF_AUTH_ANONYMOUS_ORG_ROLE=${GF_AUTH_ANONYMOUS_ORG_ROLE}" \
  -e "GF_PLUGINS_PREINSTALL=${GF_PLUGINS_PREINSTALL}" \
  -v "${GRAFANA_VOLUME}:/var/lib/grafana" \
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered/grafana-provisioning,target=/etc/grafana/provisioning,readonly" \
  "${GRAFANA_IMAGE}"

if ! wait_for_http "http://127.0.0.1:3000/api/health" "${GRAFANA_READY_TIMEOUT}"; then
  echo "Grafana failed to become ready" >&2
  container logs -n 200 "${GRAFANA_CONTAINER}" >&2 || true
  exit 1
fi

echo "Grafana is up: http://localhost:3000"
