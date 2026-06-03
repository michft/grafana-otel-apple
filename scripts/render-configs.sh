#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMPLATES_DIR="${ROOT_DIR}/configs/templates"
RENDERED_DIR="${ROOT_DIR}/configs/rendered"
GRAFANA_PROVISIONING_DIR="${RENDERED_DIR}/grafana-provisioning"

set -a
source "${ROOT_DIR}/versions.env"
if [[ -f "${ROOT_DIR}/.env" ]]; then
  source "${ROOT_DIR}/.env"
fi
set +a

STACK_NAME=${STACK_NAME:-otel}
PROMETHEUS_CONTAINER=${PROMETHEUS_CONTAINER:-${STACK_NAME}-prometheus}
LOKI_CONTAINER=${LOKI_CONTAINER:-${STACK_NAME}-loki}
TEMPO_CONTAINER=${TEMPO_CONTAINER:-${STACK_NAME}-tempo}
PYROSCOPE_CONTAINER=${PYROSCOPE_CONTAINER:-${STACK_NAME}-pyroscope}

mkdir -p "${RENDERED_DIR}"

copy_static_files() {
  cp "${TEMPLATES_DIR}/prometheus.yaml" "${RENDERED_DIR}/prometheus.yaml"
  cp "${TEMPLATES_DIR}/loki-config.yaml" "${RENDERED_DIR}/loki-config.yaml"
  cp "${TEMPLATES_DIR}/pyroscope-config.yaml" "${RENDERED_DIR}/pyroscope-config.yaml"
  cp "${TEMPLATES_DIR}/grafana-dashboards.yaml" "${RENDERED_DIR}/grafana-dashboards.yaml"
}

sync_grafana_provisioning_tree() {
  mkdir -p \
    "${GRAFANA_PROVISIONING_DIR}/datasources" \
    "${GRAFANA_PROVISIONING_DIR}/dashboards/json" \
    "${GRAFANA_PROVISIONING_DIR}/plugins" \
    "${GRAFANA_PROVISIONING_DIR}/alerting"

  cp "${RENDERED_DIR}/grafana-dashboards.yaml" \
    "${GRAFANA_PROVISIONING_DIR}/dashboards/dashboards.yaml"

  find "${GRAFANA_PROVISIONING_DIR}/dashboards/json" -type f -delete
  if [[ -d "${ROOT_DIR}/configs/dashboards/json" ]]; then
    find "${ROOT_DIR}/configs/dashboards/json" -maxdepth 1 -type f -name '*.json' \
      -exec cp {} "${GRAFANA_PROVISIONING_DIR}/dashboards/json/" \;
  fi
}

container_exists() {
  [[ "$(container inspect "$1" 2>/dev/null)" != "[]" ]]
}

container_ip() {
  local name=$1
  local raw

  raw=$(container inspect "${name}" | grep -o '"ipv4Address":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
  if [[ -z "${raw}" ]]; then
    return 1
  fi

  echo "${raw%%/*}"
}

render_template() {
  local src=$1
  local dst=$2
  shift 2

  local sed_args=()
  while [[ $# -gt 0 ]]; do
    sed_args+=(-e "s|$1|$2|g")
    shift 2
  done

  sed "${sed_args[@]}" "${src}" >"${dst}"
}

copy_static_files
sync_grafana_provisioning_tree

if container_exists "${PROMETHEUS_CONTAINER}"; then
  PROMETHEUS_IP=$(container_ip "${PROMETHEUS_CONTAINER}")
  render_template \
    "${TEMPLATES_DIR}/tempo-config.yaml" \
    "${RENDERED_DIR}/tempo-config.yaml" \
    "__PROMETHEUS_REMOTE_WRITE_URL__" "http://${PROMETHEUS_IP}:9090/api/v1/write"
  echo "Rendered tempo-config.yaml"
else
  echo "Skipping tempo-config.yaml render until ${PROMETHEUS_CONTAINER} exists"
fi

if \
  container_exists "${PROMETHEUS_CONTAINER}" && \
  container_exists "${LOKI_CONTAINER}" && \
  container_exists "${TEMPO_CONTAINER}" && \
  container_exists "${PYROSCOPE_CONTAINER}"; then
  PROMETHEUS_IP=$(container_ip "${PROMETHEUS_CONTAINER}")
  LOKI_IP=$(container_ip "${LOKI_CONTAINER}")
  TEMPO_IP=$(container_ip "${TEMPO_CONTAINER}")
  PYROSCOPE_IP=$(container_ip "${PYROSCOPE_CONTAINER}")

  render_template \
    "${TEMPLATES_DIR}/otelcol-config.yaml.tmpl" \
    "${RENDERED_DIR}/otelcol-config.yaml" \
    "__PROMETHEUS_OTLP_URL__" "http://${PROMETHEUS_IP}:9090/api/v1/otlp" \
    "__TEMPO_OTLP_HTTP_URL__" "http://${TEMPO_IP}:4418" \
    "__LOKI_OTLP_HTTP_URL__" "http://${LOKI_IP}:3100/otlp" \
    "__PYROSCOPE_URL__" "http://${PYROSCOPE_IP}:4040"

  render_template \
    "${TEMPLATES_DIR}/grafana-datasources.yaml.tmpl" \
    "${RENDERED_DIR}/grafana-datasources.yaml" \
    "__PROMETHEUS_URL__" "http://${PROMETHEUS_IP}:9090" \
    "__TEMPO_URL__" "http://${TEMPO_IP}:3200" \
    "__LOKI_URL__" "http://${LOKI_IP}:3100" \
    "__PYROSCOPE_URL__" "http://${PYROSCOPE_IP}:4040"

  cp "${RENDERED_DIR}/grafana-datasources.yaml" \
    "${GRAFANA_PROVISIONING_DIR}/datasources/datasources.yaml"

  echo "Rendered collector and Grafana configs"
else
  echo "Skipping collector/Grafana renders until all backends exist"
fi
