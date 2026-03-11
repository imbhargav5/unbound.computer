# SigNoz Operating Model

This document defines how Unbound should use SigNoz for traces, logs, sampling,
and telemetry quality checks.

## 1. Telemetry Contract

### Required resource attributes

- `service.name`
- `service.namespace`
- `deployment.environment`

### Required root-span attributes

- `operation`
- `feature`
- `request.id`
- `session.id` when applicable
- `result`

### Recommended business attributes

- `user.id_hash`
- `workspace.id`
- `account.plan`
- `experiment`
- `variant`

### Required dependency attributes

- SQLite:
  - `db.system=sqlite`
  - `db.operation`
  - `db.path_hash`
- Supabase:
  - `peer.service=supabase`
  - `http.method`
  - `http.host`
  - `operation`
  - `table`
- IPC:
  - `request.id`
  - `session.id`
  - `ipc.event_type`

### Logging rules

- Logs complement traces; they do not replace timed spans.
- Important log records should include `request.id`, `session.id`, `trace_id`, and `span_id`.
- Never emit raw user prompts or full secret-bearing payloads as telemetry attributes.

## 2. Canonical Root Operations

- Root policy: one root span per bounded user-visible intent.
- Nested technical steps become child spans under that root.
- Detached background work keeps independent daemon-owned roots.

### macOS user-intent roots

- `session.open`
- `session.create`
- `session.rename`
- `session.delete`
- `message.send`
- `claude.stop`
- `repository.add`
- `repository.remove`
- `repository.settings.update`
- `repository.list_files`
- `repository.read_file`
- `repository.write_file`
- `repository.replace_file_range`
- `git.status`
- `git.diff_file`
- `git.log`
- `git.branches`
- `git.stage`
- `git.unstage`
- `git.discard`
- `git.commit`
- `git.push`
- `gh.auth_status`
- `gh.pr_create`
- `gh.pr_view`
- `gh.pr_list`
- `gh.pr_checks`
- `gh.pr_merge`
- `terminal.run`
- `terminal.stop`
- `system.check_dependencies`
- `auth.login.start`
- `auth.complete_social`
- `auth.logout`
- `billing.usage_status`

### detached daemon roots

- `daemon.startup`
- `auth.refresh_background`
- `billing.refresh_background`
- `sync.reconcile_startup`
- `sync.message_batch`
- `sync.session_metadata`
- `sidecar.ensure_healthy`
- `sidecar.start`
- `sidecar.restart`
- `ably.publish.batch`
- `ably.runtime_status.publish`

- `daemon.health`
- `daemon.auth.status`
- `daemon.auth.login`
- `daemon.session.list`
- `daemon.session.create`
- `daemon.message.send`
- `daemon.claude.send`
- `daemon.repository.read_file`
- `daemon.terminal.run`

## 3. Async Pipeline Expectations

For retryable or background flows, instrumentation should expose:

- queue enqueue timestamp
- queue delay before processing
- processing duration
- retry count
- final outcome

Current high-priority async pipelines:

- runtime status fanout
- message sync fanout
- sidecar supervision
- Claude stream handling

## 4. Saved SigNoz Investigations

### Trace views

- End-to-end app/daemon: `service.name IN ("macos", "daemon")`
- Session open waterfall: `name = "session.open"` with columns `service.name`, `name`, `duration_nano`, `session.id`, `attempt_id`
- First-feedback send path: `name = "message.send"` with columns `service.name`, `name`, `duration_nano`, `session.id`, `attempt_id`
- Repository add compound flow: `name = "repository.add"` with columns `service.name`, `name`, `duration_nano`, `workspace.id`, `attempt_id`
- Slow Claude send: `name = "daemon.claude.send"` sorted by duration
- Daemon errors by method: `service.name = "daemon" AND hasError = true`
- Sync bottlenecks: `operation LIKE "sync.%"`

### Log views

- Daemon live logs: `service.name = "daemon"`
- Cross-runtime session view: `session.id EXISTS AND service.name IN ("macos","daemon")`
- Session open logs: `operation = "session.open"` with `trace_id`, `attempt_id`, `session_id`
- Message send logs: `operation = "message.send"` with `trace_id`, `attempt_id`, `session_id`
- Sidecar failures: `event_code LIKE "daemon.sidecar.%"`
- Runtime-status retries: `operation = "sync.runtime_status.patch"`

### Session open trace shape

Expected bounded startup tree for a populated session:

- `session.open`
  - `session.select`
  - `session.activate`
    - `session.activate.yield`
    - `session.activate.load_messages`
      - `session.load_messages.ipc`
        - `daemon.message.list`
          - daemon `ipc.handle`
          - daemon `armin.snapshot`
          - daemon `build_json`
          - daemon `ipc.response.write`
      - `session.load_messages.rows_decode`
      - `session.load_messages.state_replace`
      - `session.load_messages.refresh_messages`
      - `session.snapshot.build_wait`
      - `session.snapshot.build`
      - `session.snapshot.publish`
    - `session.activate.status_subscribe`
      - `daemon.claude.status`
      - `daemon.session.subscribe`
        - daemon `ipc.subscribe.setup`
  - `session.activate.visible_wait`

Expected end condition:

- startup settled after `load_messages` + initial `claude.status` + subscribe setup
- visible-ready after initial render or empty-state visibility

## 5. Dashboards

### Latency dashboard

- `daemon.claude.send` p50/p95/p99
- `daemon.session.list` p50/p95/p99
- IPC response write duration
- SQLite duration by operation
- Supabase request duration by operation

### Reliability dashboard

- daemon error rate by method
- sidecar restart/backoff count
- runtime-status retry count
- auth failure rate
- daemon log volume vs macOS log volume

## 6. Alerts

### High priority

- no daemon logs for a live daemon during the last 10 minutes
- no daemon spans for a live daemon during the last 10 minutes
- `daemon.claude.send` p95 regression above agreed threshold
- auth failure spike
- sidecar startup failure spike

### Medium priority

- runtime-status retry queue growth
- Supabase request error-rate increase
- repeated telemetry init/shutdown warnings

## 7. Sampling and Retention

### Local development

- traces: `always_on`
- logs: full export
- retention: short and cheap is fine

### Shared / production

- keep all error traces
- keep slow traces above threshold
- keep enterprise or high-value feature traces
- use ratio sampling only for ordinary success paths

## 8. Telemetry Quality Gates

Every tracing/exporter change should pass:

- both `daemon` and `macos` present in logs backend
- both `daemon` and `macos` present in traces backend
- no `BatchLogProcessor.Emit.AfterShutdown`
- one end-to-end request has a coherent trace
- required root-span attributes are present

## 9. Local Smoke Workflow

The local SigNoz stack is expected at `~/Code/signoz` and should be managed from this repo with:

```bash
pnpm signoz:start
pnpm signoz:status
pnpm signoz:stop
```

Run the local verification script:

```bash
./scripts/ci/signoz-smoke.sh
```

For full end-to-end validation, require both services and traces:

```bash
EXPECTED_SERVICES=daemon,macos REQUIRE_TRACES=1 ./scripts/ci/signoz-smoke.sh
```

What it checks:

- recent daemon and macOS log rows in ClickHouse
- recent daemon and macOS span rows in ClickHouse
- recent daemon resource tag presence
- latest local daemon export warnings

## 10. Rollout Priority

1. shared schema and helper APIs
2. dependency spans for SQLite and Supabase
3. async queue timing for runtime status and message sync
4. saved investigations and dashboards
5. alerts and production sampling
