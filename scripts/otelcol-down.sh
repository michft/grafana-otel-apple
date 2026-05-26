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
OTELCOL_CONTAINER=${OTELCOL_CONTAINER:-${STACK_NAME}-otelcol}

if [[ "$(container inspect "${OTELCOL_CONTAINER}" 2>/dev/null)" != "[]" ]]; then
  echo "Removing ${OTELCOL_CONTAINER}"
  container delete -f "${OTELCOL_CONTAINER}" >/dev/null
else
  echo "${OTELCOL_CONTAINER} does not exist"
fi
