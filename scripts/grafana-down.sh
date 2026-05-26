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
GRAFANA_CONTAINER=${GRAFANA_CONTAINER:-${STACK_NAME}-grafana}

if [[ "$(container inspect "${GRAFANA_CONTAINER}" 2>/dev/null)" != "[]" ]]; then
  echo "Removing ${GRAFANA_CONTAINER}"
  container delete -f "${GRAFANA_CONTAINER}" >/dev/null
else
  echo "${GRAFANA_CONTAINER} does not exist"
fi
