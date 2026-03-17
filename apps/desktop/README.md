# Unbound Desktop

Tauri desktop client for Unbound. This app is the primary macOS desktop surface and talks to `unbound-daemon` over the existing local IPC socket.

## Runtime model

- Production desktop builds do not bundle the daemon.
- `unbound-daemon` is packaged and installed separately.
- The desktop app checks daemon health and version compatibility on startup.
- If the daemon is missing, stale, or incompatible, the desktop app blocks on an install/update screen.

## Development

From the repository root:

```bash
# Run the Tauri desktop shell directly
pnpm desktop:dev

# Or run the daemon and desktop app together
pnpm daemon:dev:app
```

From `apps/desktop`:

```bash
pnpm tauri:dev
```

## Observability

The Tauri shell exports logs and traces through the shared Rust OTLP wiring used
by the daemon.

- `service.name` is `desktop`
- local dev logs are written to `~/.unbound-dev/logs/desktop.jsonl` in debug builds
- production logs are written under the resolved `UNBOUND_BASE_DIR` runtime dir

The desktop shell uses the same OTLP env contract as the daemon:

- `UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT`
- `UNBOUND_OTEL_HEADERS`
- `UNBOUND_OTEL_SAMPLER`
- `UNBOUND_OTEL_TRACES_SAMPLER_ARG`
- `UNBOUND_ENV`
- `UNBOUND_LOG_FORMAT`
- `UNBOUND_RUST_LOG`

Example local run against SigNoz:

```bash
UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 pnpm desktop:dev
```

Example smoke query after generating desktop activity:

```bash
EXPECTED_SERVICES=daemon,desktop REQUIRE_TRACES=1 ./scripts/ci/signoz-smoke.sh 1800
```

## Build

```bash
pnpm --filter @unbound/desktop build
pnpm --filter @unbound/desktop tauri:build
```

## Production packaging

The canonical macOS release path is the repo-level release script:

```bash
./scripts/release/build-macos-release.sh
```

That script produces separate desktop-app and daemon artifacts under `dist/macos/`.
