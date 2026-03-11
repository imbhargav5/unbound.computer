use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

use observability::{
    force_flush, init_with_config, shutdown, LogConfig, LogFormat, ObservabilityMode, OtlpConfig,
    OtlpSampler,
};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let endpoint = std::env::var("UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT")
        .unwrap_or_else(|_| "http://localhost:4318".to_string());
    let marker = format!(
        "init-trace-smoke-{}",
        SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis()
    );

    init_with_config(LogConfig {
        service_name: "daemon-init-smoke".to_string(),
        default_level: "info".to_string(),
        also_stderr: true,
        mode: ObservabilityMode::DevVerbose,
        log_format: LogFormat::Json,
        environment: "development".to_string(),
        otlp: Some(OtlpConfig {
            endpoint,
            headers: HashMap::new(),
            sampler: OtlpSampler::AlwaysOn,
            sampler_arg: 1.0,
        }),
        ..Default::default()
    });

    let span = tracing::info_span!("init.trace.smoke", smoke_marker = %marker);
    let _guard = span.enter();
    tracing::info!(smoke_marker = %marker, "inside smoke span");
    drop(_guard);
    drop(span);

    tokio::time::sleep(tokio::time::Duration::from_secs(8)).await;
    force_flush();
    shutdown();

    println!("marker={marker}");
    Ok(())
}
