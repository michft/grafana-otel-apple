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
TARGET=${1:-all}
FOLLOW=${FOLLOW:-false}
TAIL_LINES=${TAIL_LINES:-50}

resolve_name() {
  case "$1" in
    prometheus) echo "${PROMETHEUS_CONTAINER:-${STACK_NAME}-prometheus}" ;;
    loki) echo "${LOKI_CONTAINER:-${STACK_NAME}-loki}" ;;
    tempo) echo "${TEMPO_CONTAINER:-${STACK_NAME}-tempo}" ;;
    pyroscope) echo "${PYROSCOPE_CONTAINER:-${STACK_NAME}-pyroscope}" ;;
    grafana) echo "${GRAFANA_CONTAINER:-${STACK_NAME}-grafana}" ;;
    otelcol) echo "${OTELCOL_CONTAINER:-${STACK_NAME}-otelcol}" ;;
    *) echo "$1" ;;
  esac
}

show_logs() {
  local name
  name=$(resolve_name "$1")
  echo "== ${name} =="
  if [[ "${FOLLOW}" == "true" ]]; then
    container logs --follow -n "${TAIL_LINES}" "${name}"
  else
    container logs -n "${TAIL_LINES}" "${name}"
  fi
}

if [[ "${TARGET}" == "all" ]]; then
  if [[ "${FOLLOW}" == "true" ]]; then
    echo "FOLLOW=true requires a single service name" >&2
    exit 1
  fi

  for service in prometheus loki tempo pyroscope grafana otelcol; do
    show_logs "${service}"
  done
else
  show_logs "${TARGET}"
fi

