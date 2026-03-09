# observability

Centralized tracing and logging setup for Unbound Rust services.

## What it does

- Initializes `tracing` subscribers for structured logs.
- Exports traces and log events via OpenTelemetry OTLP when configured.
- Applies environment-oriented logging defaults:
  - `DevVerbose`: detailed local logs (file + optional stderr)
  - `ProdLight`: lightweight JSON logs to stderr

## Usage

```rust
fn main() {
    observability::init_with_config(observability::LogConfig {
        service_name: "daemon".into(),
        default_level: "debug".into(),
        mode: observability::ObservabilityMode::DevVerbose,
        log_format: observability::LogFormat::Pretty,
        otlp: Some(observability::OtlpConfig {
            endpoint: "http://localhost:4318/v1/traces".into(),
            ..Default::default()
        }),
        ..Default::default()
    });

    tracing::info!("ready");
}
```

## Dev log file

By default in `DevVerbose`, logs are written to:

```text
~/.unbound/logs/dev.jsonl
```

Callers can override `LogConfig.log_path`. The daemon now writes its dev log file under the active runtime base dir, for example:

```text
~/.unbound-dev/logs/dev.jsonl
```

## Main types

- `LogConfig`: logging + tracing configuration
- `ObservabilityMode`: `DevVerbose` or `ProdLight`
- `LogFormat`: `Pretty` or `Json`
- `OtlpConfig`: endpoint, headers, and sampler settings
- `OtlpSampler`: `AlwaysOn` or `ParentBasedTraceIdRatio`

## OTLP envs used by daemon wiring

- `UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT`
- `UNBOUND_OTEL_HEADERS`
- `UNBOUND_OTEL_SAMPLER`
- `UNBOUND_OTEL_TRACES_SAMPLER_ARG`

## SigNoz operating model

For the shared telemetry schema, saved investigations, alert/SLO guidance, and
local smoke workflow, see [SIGNOZ_OPERATING_MODEL.md](/Users/bhargavponnapalli/Code/rocketry-repos/unbound.computer/packages/observability/SIGNOZ_OPERATING_MODEL.md).
