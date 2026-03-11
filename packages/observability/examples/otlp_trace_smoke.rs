use std::error::Error as _;
use std::fmt;
use std::time::{SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use opentelemetry::trace::{Span as _, Tracer as _, TracerProvider as _};
use opentelemetry::KeyValue;
use opentelemetry_http::{Bytes, HttpClient, HttpError, Request, Response, ResponseExt};
use opentelemetry_otlp::{Protocol, WithExportConfig, WithHttpConfig};
use opentelemetry_sdk::trace::SdkTracerProvider;
use opentelemetry_sdk::Resource;

#[derive(Clone)]
struct LoggingHttpClient {
    inner: reqwest::blocking::Client,
}

impl fmt::Debug for LoggingHttpClient {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("LoggingHttpClient").finish()
    }
}

#[async_trait]
impl HttpClient for LoggingHttpClient {
    async fn send_bytes(&self, request: Request<Bytes>) -> Result<Response<Bytes>, HttpError> {
        let uri = request.uri().to_string();
        let method = request.method().clone();
        let headers = request.headers().clone();
        let body_len = request.body().len();
        eprintln!("[trace-smoke] sending {method} {uri} body_len={body_len} headers={headers:?}");

        let request = request.try_into()?;
        let mut response = match self.inner.execute(request) {
            Ok(response) => response,
            Err(err) => {
                eprintln!(
                    "[trace-smoke] request failed: {err} debug={err:?} is_connect={} is_timeout={} is_body={} is_decode={}",
                    err.is_connect(),
                    err.is_timeout(),
                    err.is_body(),
                    err.is_decode()
                );
                let mut source = err.source();
                while let Some(err) = source {
                    eprintln!("[trace-smoke] caused by: {err}");
                    source = err.source();
                }
                return Err(Box::new(err));
            }
        };
        let status = response.status();
        let headers = std::mem::take(response.headers_mut());
        let body = match response.bytes() {
            Ok(body) => body,
            Err(err) => {
                eprintln!("[trace-smoke] body read failed: {err}");
                return Err(Box::new(err));
            }
        };
        eprintln!(
            "[trace-smoke] response status={} body_len={} body={:?}",
            status,
            body.len(),
            String::from_utf8_lossy(&body)
        );

        let mut http_response = Response::builder().status(status).body(body)?;
        *http_response.headers_mut() = headers;

        Ok(http_response.error_for_status()?)
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let endpoint = std::env::var("UNBOUND_OTEL_EXPORTER_OTLP_ENDPOINT")
        .unwrap_or_else(|_| "http://localhost:4318".to_string());
    let trace_endpoint = format!("{}/v1/traces", endpoint.trim_end_matches('/'));
    let marker = format!(
        "trace-smoke-{}",
        SystemTime::now().duration_since(UNIX_EPOCH)?.as_millis()
    );

    let exporter = opentelemetry_otlp::SpanExporter::builder()
        .with_http()
        .with_http_client(LoggingHttpClient {
            inner: reqwest::blocking::Client::new(),
        })
        .with_protocol(Protocol::HttpBinary)
        .with_endpoint(trace_endpoint)
        .build()?;

    let provider = SdkTracerProvider::builder()
        .with_simple_exporter(exporter)
        .with_resource(
            Resource::builder()
                .with_attributes(vec![
                    KeyValue::new("service.name", "daemon-smoke"),
                    KeyValue::new("service.namespace", "unbound"),
                    KeyValue::new("deployment.environment", "development"),
                ])
                .build(),
        )
        .build();

    let tracer = provider.tracer("otlp-trace-smoke");
    let mut span = tracer.start("trace.smoke");
    span.set_attribute(KeyValue::new("smoke.marker", marker.clone()));
    span.set_attribute(KeyValue::new("smoke.kind", "direct-otlp"));
    let span_context = span.span_context().clone();
    println!(
        "marker={marker} trace_id={} span_id={}",
        span_context.trace_id(),
        span_context.span_id()
    );
    span.end();

    println!("force_flush={:?}", provider.force_flush());
    println!("shutdown={:?}", provider.shutdown());
    Ok(())
}
