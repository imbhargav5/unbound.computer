use std::time::{SystemTime, UNIX_EPOCH};

use opentelemetry::trace::TracerProvider as _;
use opentelemetry::KeyValue;
use opentelemetry_otlp::{Protocol, WithExportConfig, WithHttpConfig};
use opentelemetry_sdk::trace::{BatchSpanProcessor, SdkTracerProvider};
use opentelemetry_sdk::Resource;
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let endpoint = std::env::var("UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT")
        .unwrap_or_else(|_| "http://localhost:4318".to_string());
    let trace_endpoint = format!("{}/v1/traces", endpoint.trim_end_matches('/'));
    let marker = format!(
        "tracing-layer-smoke-{}",
        SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis()
    );

    let exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_http()
        .with_http_client(
            std::thread::spawn(reqwest::blocking::Client::new)
                .join()
                .unwrap_or_else(|_| reqwest::blocking::Client::new()),
        )
        .with_protocol(Protocol::HttpBinary)
        .with_endpoint(trace_endpoint)
        .build()?;

    let provider = SdkTracerProvider::builder()
        .with_span_processor(BatchSpanProcessor::builder(exporter).build())
        .with_resource(
            Resource::builder()
                .with_attributes(vec![
                    KeyValue::new("service.name", "tracing-layer-smoke"),
                    KeyValue::new("service.namespace", "unbound"),
                    KeyValue::new("deployment.environment", "development"),
                ])
                .build(),
        )
        .build();

    let tracer = provider.tracer("tracing-layer-smoke");
    tracing_subscriber::registry()
        .with(tracing_subscriber::fmt::layer().with_writer(std::io::stderr))
        .with(tracing_opentelemetry::layer().with_tracer(tracer))
        .try_init()?;

    let span = tracing::info_span!("tracing.layer.smoke", smoke_marker = %marker);
    let _guard = span.enter();
    tracing::info!(smoke_marker = %marker, "inside tracing layer smoke span");
    drop(_guard);
    drop(span);

    tokio::time::sleep(tokio::time::Duration::from_secs(8)).await;
    let _ = provider.force_flush();
    let _ = provider.shutdown();

    println!("marker={marker}");
    Ok(())
}
