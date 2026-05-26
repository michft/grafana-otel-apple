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
PYROSCOPE_CONTAINER=${PYROSCOPE_CONTAINER:-${STACK_NAME}-pyroscope}

if [[ "$(container inspect "${PYROSCOPE_CONTAINER}" 2>/dev/null)" != "[]" ]]; then
  echo "Removing ${PYROSCOPE_CONTAINER}"
  container delete -f "${PYROSCOPE_CONTAINER}" >/dev/null
else
  echo "${PYROSCOPE_CONTAINER} does not exist"
fi
