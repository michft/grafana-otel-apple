# Contributing

## Scope

This repo builds a local LGTM-style observability stack for macOS using Apple's `container` CLI.

Changes should preserve that focus:

- local developer workflow first
- Apple Containers compatibility first
- parity with the developer-facing goals of `grafana/otel-lgtm`, not literal one-image parity

## Before You Change Anything

Read these first:

- [README.md](./README.md)
- [PLAN.md](./PLAN.md)
- [docs/decisions.md](./docs/decisions.md)

Those files explain the current runtime assumptions and why some choices differ from a Docker-native setup.

## Repo Conventions

- `configs/templates/` is source-controlled input.
- `configs/rendered/` is generated output.
- `configs/rendered/grafana-provisioning/` is generated output.
- `versions.env` is the source of truth for pinned image tags.
- scripts in `scripts/` are the operational interface for the stack.

Do not treat generated files as the primary place to make changes. Update templates or scripts, then re-render.

## Generated Files

If you change config templates, backend wiring, or provisioning behavior, regenerate runtime output with:

```sh
./scripts/render-configs.sh
```

Generated files under `configs/rendered/` may change as a consequence. That is expected.

## Typical Validation Flow

For most changes, use the smallest verification loop that matches the change:

```sh
./scripts/lgtm-status.sh
./scripts/smoke-test.sh
```

If you are working on one service only, prefer the dedicated scripts:

```sh
./scripts/prometheus-up.sh
./scripts/loki-up.sh
./scripts/tempo-up.sh
./scripts/pyroscope-up.sh
./scripts/otelcol-up.sh
./scripts/grafana-up.sh
```

Matching teardown scripts exist for each service.

## Apple Containers Constraints

Current repo behavior assumes:

- directory bind mounts are used instead of single-file bind mounts
- backend URLs are rendered by container IP
- several services need `0:0` on fresh Apple named volumes
- Loki is internal-only by default

If you change one of those assumptions, update:

- [README.md](./README.md)
- [docs/decisions.md](./docs/decisions.md)
- any affected scripts

## Documentation Expectations

When behavior changes, update the docs in the same change.

Usually that means:

- `README.md` for user-facing setup or behavior
- `docs/decisions.md` for runtime-specific reasoning
- `CHANGELOG.md` for notable repo changes

## Pull Request Labels

PRs are automatically labeled with a `vouch:*` trust status and a `size:*` diff size based on changed lines.

If you are an external contributor, expect `vouch:unvouched` until we explicitly add you to [.github/VOUCHED.txt](./.github/VOUCHED.txt).

## Keep Changes Narrow

Prefer small, scriptable, reproducible changes over broad refactors.

In particular:

- keep Apple Containers compatibility explicit
- keep source-of-truth files separate from generated output
- keep the difference between this repo and upstream `grafana/otel-lgtm` documented clearly
