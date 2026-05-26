# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog.

## [Unreleased]

### Added

- bootstrap, orchestration, status, logs, and smoke-test scripts for the Apple Containers stack
- dedicated up/down scripts for Prometheus, Loki, Tempo, Pyroscope, OpenTelemetry Collector, and Grafana
- rendered config pipeline for backend services, collector config, and Grafana provisioning
- repo standards files: `README.md`, `LICENSE`, and `CHANGELOG.md`

### Changed

- moved runtime config generation to directory-mounted rendered output to match Apple Containers bind-mount behavior
- documented how the decomposed Apple Containers stack differs from the upstream `grafana/otel-lgtm` image

