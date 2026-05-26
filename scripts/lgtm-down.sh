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
REMOVE_VOLUMES=${REMOVE_VOLUMES:-false}

for name in \
  "${OTELCOL_CONTAINER:-${STACK_NAME}-otelcol}" \
  "${GRAFANA_CONTAINER:-${STACK_NAME}-grafana}" \
  "${TEMPO_CONTAINER:-${STACK_NAME}-tempo}" \
  "${PYROSCOPE_CONTAINER:-${STACK_NAME}-pyroscope}" \
  "${LOKI_CONTAINER:-${STACK_NAME}-loki}" \
  "${PROMETHEUS_CONTAINER:-${STACK_NAME}-prometheus}"; do
  if [[ "$(container inspect "${name}" 2>/dev/null)" != "[]" ]]; then
    echo "Removing ${name}"
    container delete -f "${name}" >/dev/null
  fi
done

if [[ "${REMOVE_VOLUMES}" == "true" ]]; then
  for volume_name in \
    "${GRAFANA_VOLUME:-${STACK_NAME}-grafana-data}" \
    "${PROMETHEUS_VOLUME:-${STACK_NAME}-prometheus-data}" \
    "${LOKI_VOLUME:-${STACK_NAME}-loki-data}" \
    "${TEMPO_VOLUME:-${STACK_NAME}-tempo-data}" \
    "${PYROSCOPE_VOLUME:-${STACK_NAME}-pyroscope-data}"; do
    if container volume inspect "${volume_name}" >/dev/null 2>&1; then
      echo "Removing volume ${volume_name}"
      container volume delete "${volume_name}" >/dev/null
    fi
  done
fi

echo "Stack is down"
