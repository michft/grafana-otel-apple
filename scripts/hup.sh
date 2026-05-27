#!/usr/bin/env bash

# My AI agent startup script, working with https://github.com/pingdotgg/t3code
# and https://chatgpt.com/codex/

# Check LGTM stack status
status_output=$(~/src/otel/scripts/lgtm-status.sh 2>&1)

# Check if any containers are not running or missing
if echo "$status_output" | grep -E "(missing|exited|paused)" > /dev/null; then
  echo "LGTM stack is not fully running, stopping what is running..."
  ~/src/otel/scripts/lgtm-down.sh
  echo "LGTM stack starting..."
  ~/src/otel/scripts/lgtm-up.sh
else
  echo "LGTM stack is running"
fi

# Set OTLP environment variables for T3 Code
export T3CODE_OTLP_TRACES_URL=http://localhost:4318/v1/traces
export T3CODE_OTLP_METRICS_URL=http://localhost:4318/v1/metrics
export T3CODE_OTLP_SERVICE_NAME=t3-desktop
export T3CODE_TRACE_MIN_LEVEL=Info
export T3CODE_TRACE_TIMING_ENABLED=true

# Launch T3 Code
"/Applications/T3 Code (Alpha).app/Contents/MacOS/T3 Code (Alpha)"
