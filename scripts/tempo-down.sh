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
TEMPO_CONTAINER=${TEMPO_CONTAINER:-${STACK_NAME}-tempo}

if [[ "$(container inspect "${TEMPO_CONTAINER}" 2>/dev/null)" != "[]" ]]; then
  container delete -f "${TEMPO_CONTAINER}"
fi

