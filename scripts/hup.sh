#!/usr/bin/env bash

# Start LGTM stack
~/src/otel/scripts/lgtm-up.sh

# Set OTLP environment variables for T3 Code
export T3CODE_OTLP_TRACES_URL=http://localhost:4318/v1/traces
export T3CODE_OTLP_METRICS_URL=http://localhost:4318/v1/metrics
export T3CODE_OTLP_SERVICE_NAME=t3-desktop
export T3CODE_TRACE_MIN_LEVEL=Info
export T3CODE_TRACE_TIMING_ENABLED=true

# Launch T3 Code
"/Applications/T3 Code (Alpha).app/Contents/MacOS/T3 Code (Alpha)"
