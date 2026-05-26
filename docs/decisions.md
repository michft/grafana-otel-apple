# Decisions

## Initial skeleton decisions

- The repo keeps upstream-style config in `configs/templates/` and writes generated runtime config to `configs/rendered/`.
- The first implementation assumes Apple `container` networking is reliable by IP, not by Docker-style container-name DNS.
- Tempo is rendered after Prometheus exists because its metrics generator remote-write target depends on Prometheus.
- Grafana and the OpenTelemetry Collector are rendered after all backends exist because their datasource/exporter URLs depend on backend container IPs.
- OBI is intentionally deferred from the first implementation.
- Apple `container` bind mounts are currently treated as directory mounts in this repo flow, so runtime config is mounted as a rendered directory rather than as individual files.
- Prometheus currently runs as `0:0` when backed by an Apple named volume because the default `nobody` user could not write its TSDB files on a fresh volume.
- Loki currently runs as `0:0` for the same reason: the default image user `10001` could not initialize a fresh Apple named volume.
- Loki readiness is materially slower than process start on this machine. A healthy container reached `/ready` in about 82 seconds, so isolated Loki startup should wait longer than Prometheus.
- Tempo also needed `0:0` on a fresh Apple named volume; the default `10001:10001` user could not initialize `/data/tempo`.
- Tempo readiness lag was short once permissions were fixed. On this machine `/ready` flipped healthy about one second after the initial ingester readiness gate.

## Expected next decisions

- Confirm the exact standalone image tags and entrypoint expectations for each pinned service.
- Decide whether to keep IP-based rendering or introduce Apple-local DNS/domain setup.
- Decide whether Loki should remain internal-only or gain an optional published debug port.
