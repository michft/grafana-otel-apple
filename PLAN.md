# PLAN: Apple Containers OpenTelemetry LGTM-Style Deployment

## Goal

Build a local OpenTelemetry stack on macOS using Apple's `container` CLI that reaches the same developer-facing end-state as `grafana/otel-lgtm`:

- OTLP ingest on `4317` and `4318`
- Grafana on `3000`
- Tempo on `3200`
- Pyroscope on `4040`
- Prometheus on `9090`
- logs, metrics, traces, and profiles wired together in Grafana
- one command to bring the stack up, one command to tear it down, persistent data by default

This should be a development/demo/test stack, not a production design, matching the intent of `docker-otel-lgtm`.

## What "same end-state" means

From a user point of view, the Apple Containers deployment should behave like the single LGTM image:

1. Applications can export OTLP data to `http://localhost:4318` or `grpc://localhost:4317`.
2. Grafana opens at `http://localhost:3000` with working datasources for Prometheus, Loki, Tempo, and Pyroscope.
3. Metrics land in Prometheus.
4. Traces land in Tempo and link back to logs and exemplars.
5. Logs land in Loki.
6. Profiles land in Pyroscope.
7. The stack can be started and stopped repeatably without manual per-service setup.

## Verified constraints on this machine

- Repo state on May 26, 2026: empty git repo, so this is greenfield.
- Local Apple Containers runtime is installed: `container` CLI `0.12.3`.
- `container system status` is `running`.
- Current CLI surface includes images, containers, networks, volumes, port publishing, and system management.
- Current CLI does not expose a Compose-like subcommand, so this repo needs its own orchestration scripts.
- Quick runtime check: containers on a custom Apple network could reach each other by IP, but container-name DNS did not resolve in a simple Alpine test. The plan should therefore treat service discovery as explicit bootstrap work, not assumed Docker-style DNS.

## Important upstream facts to mirror

The current `grafana/otel-lgtm` image bundles:

- OpenTelemetry Collector
- Prometheus
- Tempo
- Loki
- Pyroscope
- Grafana
- optional OBI eBPF auto-instrumentation

The current upstream image pins these versions in its Dockerfile:

- Grafana `v13.0.1`
- Prometheus `v3.11.3`
- Tempo `v2.10.5`
- Loki `v3.7.2`
- Pyroscope `v2.0.2`
- OpenTelemetry Collector `v0.152.0`
- OBI `v0.9.0`

Its internal topology is also important:

- OTel Collector receives OTLP on `4317` and `4318`
- Collector exports metrics to Prometheus OTLP at `:9090/api/v1/otlp`
- Collector exports traces to Tempo OTLP HTTP at `:4418`
- Collector exports logs to Loki OTLP HTTP at `:3100/otlp`
- Collector exports profiles to Pyroscope at `:4040`
- Grafana provisions datasources pointing at Prometheus, Tempo, Loki, and Pyroscope

## Recommendation

The deliverable should be the decomposed stack itself:

- use the monolithic `grafana/otel-lgtm` image only as the upstream reference implementation
- launch separate Apple-managed containers for Collector, Prometheus, Tempo, Loki, Pyroscope, and Grafana
- preserve the monolith's host ports, config semantics, and user-visible behavior

The main engineering job is not "can Apple run the monolith"; it is "how do we split the monolith into separate launchable Apple containers without losing the same local LGTM experience".

## Architecture for the repo-owned stack

### Containers

- `otelcol`
  - image: `otel/opentelemetry-collector-contrib`
  - published ports: `4317`, `4318`
  - internal health: `13133`
- `prometheus`
  - image: `prom/prometheus`
  - published port: `9090`
- `tempo`
  - image: `grafana/tempo`
  - published port: `3200`
  - internal OTLP receiver remains private on `4417/4418`
- `loki`
  - image: `grafana/loki`
  - internal only by default
- `pyroscope`
  - image: `grafana/pyroscope`
  - published port: `4040`
- `grafana`
  - image: `grafana/grafana`
  - published port: `3000`

### Networking

- Create one dedicated Apple Containers network, for example `otel-net`.
- Do not assume Docker-style service-name DNS inside that network.
- Instead, make startup deterministic:
  1. create the backend containers first
  2. inspect their assigned IPs
  3. render config files from templates with those IPs
  4. start Grafana and OTel Collector using the rendered configs

If later testing shows a reliable DNS strategy with Apple Containers, the rendered-IP step can be simplified away.

### Storage

Use Apple-managed named volumes for persistence:

- `otel-grafana-data`
- `otel-prometheus-data`
- `otel-loki-data`
- `otel-tempo-data`
- `otel-pyroscope-data`

Keep configs in the repo and mount them read-only.

### Configuration source of truth

Reuse the upstream `docker-otel-lgtm` config shapes as closely as possible:

- `prometheus.yaml`
- `loki-config.yaml`
- `tempo-config.yaml`
- `pyroscope-config.yaml`
- `otelcol-config.yaml`
- Grafana datasource provisioning
- Grafana dashboard provisioning

Only change what is needed for:

- image-specific filesystem paths
- Apple-Containers-friendly mounts
- dynamic service IPs

## Proposed repo layout

```text
.
├── PLAN.md
├── .env.example
├── versions.env
├── configs/
│   ├── templates/
│   │   ├── grafana-datasources.yaml.tmpl
│   │   ├── otelcol-config.yaml.tmpl
│   │   ├── prometheus.yaml
│   │   ├── loki-config.yaml
│   │   ├── tempo-config.yaml
│   │   ├── pyroscope-config.yaml
│   │   └── grafana-dashboards.yaml
│   ├── dashboards/
│   └── rendered/
├── scripts/
│   ├── bootstrap.sh
│   ├── lgtm-up.sh
│   ├── lgtm-down.sh
│   ├── lgtm-logs.sh
│   ├── lgtm-status.sh
│   ├── render-configs.sh
│   └── smoke-test.sh
└── docs/
    └── decisions.md
```

## Delivery plan

### Phase 1: Decompose into first-class services

Implement the six-container stack using pinned upstream component images.

Acceptance:

- same host ports as the upstream monolith
- Grafana datasources auto-provisioned
- OTel Collector successfully exports all four signals
- stack survives restart with persistent volumes intact

### Phase 2: Scripted orchestration

Implement repo-owned orchestration around the Apple CLI:

- `scripts/bootstrap.sh`
  - verify `container` installed
  - ensure `container system start`
  - create network
  - create volumes
  - pull pinned images
- `scripts/render-configs.sh`
  - inspect backend container IPs
  - render collector and Grafana datasource templates
- `scripts/lgtm-up.sh`
  - create or start backends
  - render configs
  - create or start collector and Grafana
  - wait on health endpoints
  - print URLs and credentials
- `scripts/lgtm-down.sh`
  - stop/remove containers
  - preserve volumes by default
- `scripts/lgtm-status.sh`
  - show container state and health URLs
- `scripts/lgtm-logs.sh`
  - tail logs from one or all services

Acceptance:

- one-command up/down workflow
- idempotent reruns
- clear failure messages when a service is unhealthy

### Phase 3: Smoke tests and parity checks

Add a scripted verification path:

- send a sample trace/span via OTLP HTTP
- send a sample metric
- send a sample log
- optionally send a sample profile if a simple fixture is practical
- verify:
  - Prometheus query endpoint responds
  - Tempo ready endpoint responds
  - Loki ready endpoint responds
  - Grafana health endpoint responds
  - the exposed host ports and basic UX match the upstream monolith's documented behavior

## Non-goals for the first pass

- Kubernetes deployment
- production HA, durability, auth hardening, or remote object storage
- automatic eBPF host instrumentation parity with OBI
- perfect drop-in compatibility with every helper in the upstream repo

## OBI / eBPF decision

Defer OBI from the first implementation.

Reason:

- the upstream OBI mode assumes Linux host-style capabilities such as host PID access and privileged eBPF instrumentation
- Apple `container` runs Linux containers in lightweight VMs on macOS
- even if OBI can later be made to work for Linux workloads inside those guests, that is not the same as parity with instrumenting arbitrary macOS host processes

Treat OBI as a separate follow-up spike after the base LGTM stack works.

## Risks and mitigations

### 1. No reliable built-in service-name resolution

Risk:

- configs that assume `http://loki:3100` or `http://tempo:3200` may not work

Mitigation:

- render configs from inspected IPs at startup
- keep the rendered files ephemeral and regenerate on every `up`

### 2. Higher resource overhead than Docker Desktop

Risk:

- Apple Containers uses lightweight VMs for Linux containers, so six separate services may be materially heavier than one bundled image

Mitigation:

- cap CPU and memory per container
- keep resource limits configurable in `.env`
- document the expected overhead tradeoff versus the bundled image

### 3. Filesystem path mismatches across upstream images

Risk:

- upstream single-image config paths do not map 1:1 onto standalone images

Mitigation:

- keep configs close to upstream semantics, but adjust paths per image deliberately
- document each path decision in `docs/decisions.md`

### 4. Version skew across independently pinned images

Risk:

- a new Grafana image or Collector image may break the expected wiring

Mitigation:

- pin versions in `versions.env`
- start from the exact versions used by the current upstream `docker-otel-lgtm` Dockerfile

## Concrete first implementation order

1. Add `versions.env` with versions copied from upstream.
2. Add `.env.example` for runtime overrides such as Grafana admin credentials.
3. Add `configs/templates/otelcol-config.yaml.tmpl`.
4. Add `configs/templates/grafana-datasources.yaml.tmpl`.
5. Add near-verbatim upstream configs for Prometheus, Loki, Tempo, Pyroscope, and dashboards.
6. Implement `scripts/bootstrap.sh`.
7. Implement `scripts/lgtm-up.sh` with backend-first startup and IP inspection.
8. Implement `scripts/lgtm-down.sh`, `lgtm-status.sh`, and `lgtm-logs.sh`.
9. Implement `scripts/smoke-test.sh`.
10. Compare the decomposed stack against the upstream monolith behavior and ports.

## Definition of done

This work is done when:

- a fresh machine with Apple `container` installed can run one bootstrap command and one up command
- the stack exposes the same host ports as `grafana/otel-lgtm`
- sample OTLP traffic reaches the correct backends
- Grafana opens with working preconfigured datasources
- data persists across teardown/restart unless the user explicitly resets volumes
- the repo contains enough scripts and docs that Docker is not required for day-to-day use

## References

- Grafana LGTM repo: <https://github.com/grafana/docker-otel-lgtm>
- Grafana LGTM docs: <https://grafana.com/docs/opentelemetry/docker-lgtm/>
- Apple `container` repo: <https://github.com/apple/container>
