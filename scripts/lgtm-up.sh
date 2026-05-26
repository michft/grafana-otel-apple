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
OTELCOL_CONTAINER=${OTELCOL_CONTAINER:-${STACK_NAME}-otelcol}

GRAFANA_VOLUME=${GRAFANA_VOLUME:-${STACK_NAME}-grafana-data}
PROMETHEUS_VOLUME=${PROMETHEUS_VOLUME:-${STACK_NAME}-prometheus-data}
LOKI_VOLUME=${LOKI_VOLUME:-${STACK_NAME}-loki-data}
TEMPO_VOLUME=${TEMPO_VOLUME:-${STACK_NAME}-tempo-data}
PYROSCOPE_VOLUME=${PYROSCOPE_VOLUME:-${STACK_NAME}-pyroscope-data}

PROMETHEUS_CPUS=${PROMETHEUS_CPUS:-1}
PROMETHEUS_MEMORY=${PROMETHEUS_MEMORY:-1G}
LOKI_CPUS=${LOKI_CPUS:-1}
LOKI_MEMORY=${LOKI_MEMORY:-1G}
TEMPO_CPUS=${TEMPO_CPUS:-1}
TEMPO_MEMORY=${TEMPO_MEMORY:-1G}
PYROSCOPE_CPUS=${PYROSCOPE_CPUS:-1}
PYROSCOPE_MEMORY=${PYROSCOPE_MEMORY:-1G}
GRAFANA_CPUS=${GRAFANA_CPUS:-1}
GRAFANA_MEMORY=${GRAFANA_MEMORY:-1G}
OTELCOL_CPUS=${OTELCOL_CPUS:-1}
OTELCOL_MEMORY=${OTELCOL_MEMORY:-1G}

GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD:-admin}
GF_AUTH_ANONYMOUS_ENABLED=${GF_AUTH_ANONYMOUS_ENABLED:-true}
GF_AUTH_ANONYMOUS_ORG_ROLE=${GF_AUTH_ANONYMOUS_ORG_ROLE:-Admin}
GF_PLUGINS_PREINSTALL=${GF_PLUGINS_PREINSTALL:-grafana-pyroscope-app,grafana-llm-app}

delete_if_exists() {
  if [[ "$(container inspect "$1" 2>/dev/null)" != "[]" ]]; then
    echo "Removing existing container $1"
    container delete -f "$1" >/dev/null
  fi
}

wait_for_http() {
  local label=$1
  local url=$2
  local attempts=${3:-60}
  local i

  for ((i = 1; i <= attempts; i++)); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      echo "${label} is ready: ${url}"
      return 0
    fi
    sleep 1
  done

  echo "Timed out waiting for ${label}: ${url}" >&2
  return 1
}

"${ROOT_DIR}/scripts/bootstrap.sh"

for name in \
  "${OTELCOL_CONTAINER}" \
  "${GRAFANA_CONTAINER}" \
  "${TEMPO_CONTAINER}" \
  "${PYROSCOPE_CONTAINER}" \
  "${LOKI_CONTAINER}" \
  "${PROMETHEUS_CONTAINER}"; do
  delete_if_exists "${name}"
done

"${ROOT_DIR}/scripts/render-configs.sh"

container run -d \
  --name "${PROMETHEUS_CONTAINER}" \
  --network "${STACK_NETWORK}" \
  --cpus "${PROMETHEUS_CPUS}" \
  --memory "${PROMETHEUS_MEMORY}" \
  -p 9090:9090 \
  -v "${PROMETHEUS_VOLUME}:/prometheus" \
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered/prometheus.yaml,target=/etc/prometheus/prometheus.yml,readonly" \
  "${PROMETHEUS_IMAGE}" \
  --web.enable-remote-write-receiver \
  --web.enable-otlp-receiver \
  --enable-feature=exemplar-storage \
  --storage.tsdb.path=/prometheus \
  --config.file=/etc/prometheus/prometheus.yml

container run -d \
  --name "${LOKI_CONTAINER}" \
  --network "${STACK_NETWORK}" \
  --cpus "${LOKI_CPUS}" \
  --memory "${LOKI_MEMORY}" \
  -v "${LOKI_VOLUME}:/data/loki" \
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered/loki-config.yaml,target=/etc/loki/config.yaml,readonly" \
  "${LOKI_IMAGE}" \
  -config.file=/etc/loki/config.yaml

container run -d \
  --name "${PYROSCOPE_CONTAINER}" \
  --network "${STACK_NETWORK}" \
  --cpus "${PYROSCOPE_CPUS}" \
  --memory "${PYROSCOPE_MEMORY}" \
  -p 4040:4040 \
  -v "${PYROSCOPE_VOLUME}:/data/pyroscope" \
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered/pyroscope-config.yaml,target=/etc/pyroscope/config.yaml,readonly" \
  "${PYROSCOPE_IMAGE}" \
  server \
  -config.file=/etc/pyroscope/config.yaml

"${ROOT_DIR}/scripts/render-configs.sh"

if [[ ! -f "${ROOT_DIR}/configs/rendered/tempo-config.yaml" ]]; then
  echo "Missing rendered tempo config" >&2
  exit 1
fi

container run -d \
  --name "${TEMPO_CONTAINER}" \
  --network "${STACK_NETWORK}" \
  --cpus "${TEMPO_CPUS}" \
  --memory "${TEMPO_MEMORY}" \
  -p 3200:3200 \
  -v "${TEMPO_VOLUME}:/data/tempo" \
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered/tempo-config.yaml,target=/etc/tempo/tempo.yaml,readonly" \
  "${TEMPO_IMAGE}" \
  -config.file=/etc/tempo/tempo.yaml

"${ROOT_DIR}/scripts/render-configs.sh"

if [[ ! -f "${ROOT_DIR}/configs/rendered/grafana-datasources.yaml" ]]; then
  echo "Missing rendered Grafana datasources config" >&2
  exit 1
fi

if [[ ! -f "${ROOT_DIR}/configs/rendered/otelcol-config.yaml" ]]; then
  echo "Missing rendered otelcol config" >&2
  exit 1
fi

container run -d \
  --name "${GRAFANA_CONTAINER}" \
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
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered/grafana-datasources.yaml,target=/etc/grafana/provisioning/datasources/datasources.yaml,readonly" \
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered/grafana-dashboards.yaml,target=/etc/grafana/provisioning/dashboards/dashboards.yaml,readonly" \
  --mount "type=bind,source=${ROOT_DIR}/configs/dashboards,target=/etc/grafana/provisioning/dashboards/json,readonly" \
  "${GRAFANA_IMAGE}"

container run -d \
  --name "${OTELCOL_CONTAINER}" \
  --network "${STACK_NETWORK}" \
  --cpus "${OTELCOL_CPUS}" \
  --memory "${OTELCOL_MEMORY}" \
  -p 4317:4317 \
  -p 4318:4318 \
  --mount "type=bind,source=${ROOT_DIR}/configs/rendered/otelcol-config.yaml,target=/etc/otelcol/config.yaml,readonly" \
  "${OTELCOL_IMAGE}" \
  --feature-gates=service.profilesSupport \
  --config=/etc/otelcol/config.yaml

wait_for_http "Prometheus" "http://127.0.0.1:9090/api/v1/status/runtimeinfo"
wait_for_http "Tempo" "http://127.0.0.1:3200/ready"
wait_for_http "Pyroscope" "http://127.0.0.1:4040/ready"
wait_for_http "Grafana" "http://127.0.0.1:3000/api/health"
wait_for_http "OpenTelemetry Collector" "http://127.0.0.1:13133/ready" 5 || true

echo "LGTM-style stack is up"
echo "Grafana: http://localhost:3000"
echo "OTLP gRPC: localhost:4317"
echo "OTLP HTTP: http://localhost:4318"
echo "Prometheus: http://localhost:9090"
echo "Tempo: http://localhost:3200"
echo "Pyroscope: http://localhost:4040"
