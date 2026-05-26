# Decisions

## Initial skeleton decisions

- The repo keeps upstream-style config in `configs/templates/` and writes generated runtime config to `configs/rendered/`.
- The first implementation assumes Apple `container` networking is reliable by IP, not by Docker-style container-name DNS.
- Tempo is rendered after Prometheus exists because its metrics generator remote-write target depends on Prometheus.
- Grafana and the OpenTelemetry Collector are rendered after all backends exist because their datasource/exporter URLs depend on backend container IPs.
- OBI is intentionally deferred from the first implementation.

## Expected next decisions

- Confirm the exact standalone image tags and entrypoint expectations for each pinned service.
- Decide whether to keep IP-based rendering or introduce Apple-local DNS/domain setup.
- Decide whether Loki should remain internal-only or gain an optional published debug port.

