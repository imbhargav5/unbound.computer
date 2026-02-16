//! Remote sink export (PostHog + Sentry) with runtime-local policy enforcement.

use crate::json_layer::LogEntry;
use crate::{LogConfig, ObservabilityMode, SamplingConfig};
use reqwest::blocking::Client;
use serde::Serialize;
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap};
use std::sync::mpsc::{sync_channel, Receiver, SyncSender, TrySendError};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const DEFAULT_POSTHOG_HOST: &str = "https://us.i.posthog.com";
const DEFAULT_BATCH_SIZE: usize = 50;
const DEFAULT_QUEUE_CAPACITY: usize = 2_000;
const DEFAULT_FLUSH_INTERVAL_MS: u64 = 2_000;

const DENYLIST_KEYS: [&str; 13] = [
    "token",
    "access_token",
    "refresh_token",
    "authorization",
    "cookie",
    "password",
    "secret",
    "private_key",
    "session_secret",
    "apnstoken",
    "pushtoken",
    "content_encrypted",
    "content_nonce",
];

const PROD_ALLOWED_FIELDS: [&str; 9] = [
    "request_id",
    "session_id",
    "device_id_hash",
    "user_id_hash",
    "trace_id",
    "span_id",
    "app_version",
    "build_version",
    "os_version",
];

#[derive(Default)]
struct CorrelationFields {
    request_id: Option<String>,
    session_id: Option<String>,
    device_id_hash: Option<String>,
    user_id_hash: Option<String>,
    trace_id: Option<String>,
    span_id: Option<String>,
}

#[derive(Clone)]
pub struct RemoteExporter {
    sender: SyncSender<ExportEnvelope>,
    mode: ObservabilityMode,
    sampling: SamplingConfig,
    environment: String,
}

#[derive(Clone)]
struct ExportEnvelope {
    posthog: Option<PosthogEvent>,
    sentry: Option<SentryEnvelope>,
}

#[derive(Clone, Debug, Serialize)]
struct PosthogEvent {
    event: String,
    distinct_id: String,
    properties: Map<String, Value>,
    timestamp: String,
}

#[derive(Clone, Debug, Serialize)]
struct PosthogBatchPayload {
    api_key: String,
    batch: Vec<PosthogEvent>,
    sent_at: String,
}

#[derive(Clone, Debug)]
struct SentryEnvelope {
    level: String,
    message: String,
    tags: BTreeMap<String, String>,
}

#[derive(Clone, Debug)]
struct PosthogSinkConfig {
    api_key: String,
    host: String,
    batch_size: usize,
    queue_capacity: usize,
    flush_interval_ms: u64,
}

impl PosthogSinkConfig {
    fn endpoint(&self) -> String {
        let host = self.host.trim_end_matches('/');
        format!("{host}/batch/")
    }
}

#[derive(Clone, Debug)]
struct SentrySinkConfig {
    dsn: String,
}

impl RemoteExporter {
    pub fn from_config(config: &LogConfig) -> Option<Self> {
        let posthog_cfg = config.posthog.as_ref().map(|posthog| PosthogSinkConfig {
            api_key: posthog.api_key.clone(),
            host: if posthog.host.trim().is_empty() {
                DEFAULT_POSTHOG_HOST.to_string()
            } else {
                posthog.host.clone()
            },
            batch_size: posthog.batch_size.max(1),
            queue_capacity: posthog.queue_capacity.max(100),
            flush_interval_ms: posthog.flush_interval_ms.max(100),
        });
        let sentry_cfg = config.sentry.as_ref().map(|sentry| SentrySinkConfig {
            dsn: sentry.dsn.clone(),
        });

        if posthog_cfg.is_none() && sentry_cfg.is_none() {
            return None;
        }

        let queue_capacity = posthog_cfg
            .as_ref()
            .map(|cfg| cfg.queue_capacity)
            .unwrap_or(DEFAULT_QUEUE_CAPACITY);

        let (sender, receiver) = sync_channel(queue_capacity);

        std::thread::Builder::new()
            .name("observability-remote-sink".to_string())
            .spawn(move || run_sink_worker(receiver, posthog_cfg, sentry_cfg))
            .expect("failed to spawn observability remote sink worker");

        Some(Self {
            sender,
            mode: config.mode,
            sampling: config.sampling.clone(),
            environment: config.environment.clone(),
        })
    }

    pub fn export(&self, entry: &LogEntry) {
        if !should_sample(entry, &self.sampling) {
            return;
        }

        let envelope = build_export_envelope(entry, self.mode, &self.environment);
        if envelope.posthog.is_none() && envelope.sentry.is_none() {
            return;
        }

        match self.sender.try_send(envelope) {
            Ok(()) => {}
            Err(TrySendError::Full(_)) => {
                // Best effort: never block producer path.
            }
            Err(TrySendError::Disconnected(_)) => {}
        }
    }
}

fn run_sink_worker(
    receiver: Receiver<ExportEnvelope>,
    posthog_cfg: Option<PosthogSinkConfig>,
    sentry_cfg: Option<SentrySinkConfig>,
) {
    let posthog_client = posthog_cfg
        .as_ref()
        .map(|_| Client::builder().timeout(Duration::from_secs(5)).build())
        .transpose()
        .ok()
        .flatten();

    let sentry_guard = sentry_cfg.as_ref().map(|cfg| {
        sentry::init((
            cfg.dsn.clone(),
            sentry::ClientOptions {
                attach_stacktrace: false,
                ..Default::default()
            },
        ))
    });

    let mut batch = Vec::new();
    let batch_size = posthog_cfg
        .as_ref()
        .map(|cfg| cfg.batch_size)
        .unwrap_or(DEFAULT_BATCH_SIZE);
    let flush_interval = Duration::from_millis(
        posthog_cfg
            .as_ref()
            .map(|cfg| cfg.flush_interval_ms)
            .unwrap_or(DEFAULT_FLUSH_INTERVAL_MS),
    );

    loop {
        match receiver.recv_timeout(flush_interval) {
            Ok(envelope) => {
                if let Some(event) = envelope.posthog {
                    batch.push(event);
                }
                if let Some(sentry_event) = envelope.sentry {
                    capture_sentry_event(&sentry_event);
                }
                if batch.len() >= batch_size {
                    flush_posthog_batch(&mut batch, posthog_cfg.as_ref(), posthog_client.as_ref());
                }
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                flush_posthog_batch(&mut batch, posthog_cfg.as_ref(), posthog_client.as_ref());
            }
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                flush_posthog_batch(&mut batch, posthog_cfg.as_ref(), posthog_client.as_ref());
                break;
            }
        }
    }

    drop(sentry_guard);
}

fn flush_posthog_batch(
    batch: &mut Vec<PosthogEvent>,
    posthog_cfg: Option<&PosthogSinkConfig>,
    client: Option<&Client>,
) {
    let Some(cfg) = posthog_cfg else {
        batch.clear();
        return;
    };
    let Some(client) = client else {
        batch.clear();
        return;
    };
    if batch.is_empty() {
        return;
    }

    let payload = PosthogBatchPayload {
        api_key: cfg.api_key.clone(),
        batch: std::mem::take(batch),
        sent_at: now_rfc3339_fallback(),
    };

    let _ = client.post(cfg.endpoint()).json(&payload).send();
}

fn capture_sentry_event(event: &SentryEnvelope) {
    let level = match event.level.as_str() {
        "ERROR" => sentry::Level::Error,
        "WARN" => sentry::Level::Warning,
        _ => sentry::Level::Info,
    };

    sentry::with_scope(
        |scope| {
            for (k, v) in &event.tags {
                scope.set_tag(k, v);
            }
        },
        || {
            sentry::capture_message(&event.message, level);
        },
    );
}

fn build_export_envelope(
    entry: &LogEntry,
    mode: ObservabilityMode,
    environment: &str,
) -> ExportEnvelope {
    let props = build_posthog_properties(entry, mode, environment);

    let distinct_id = props
        .get("device_id_hash")
        .and_then(|v| v.as_str())
        .or_else(|| props.get("user_id_hash").and_then(|v| v.as_str()))
        .map(|s| s.to_string())
        .unwrap_or_else(|| format!("{}-{}", entry.service, entry.pid));

    let posthog = Some(PosthogEvent {
        event: "app_log".to_string(),
        distinct_id,
        properties: props.clone(),
        timestamp: entry.timestamp.clone(),
    });

    let sentry = if entry.level == "ERROR" || entry.level == "WARN" {
        let mut tags = BTreeMap::new();
        insert_tag_from_props(&mut tags, &props, "runtime");
        insert_tag_from_props(&mut tags, &props, "service");
        insert_tag_from_props(&mut tags, &props, "component");
        insert_tag_from_props(&mut tags, &props, "event_code");
        insert_tag_from_props(&mut tags, &props, "request_id");
        insert_tag_from_props(&mut tags, &props, "session_id");
        insert_tag_from_props(&mut tags, &props, "device_id_hash");
        insert_tag_from_props(&mut tags, &props, "user_id_hash");
        insert_tag_from_props(&mut tags, &props, "trace_id");
        insert_tag_from_props(&mut tags, &props, "span_id");

        let message = props
            .get("event_code")
            .and_then(|v| v.as_str())
            .unwrap_or("observability.remote.error")
            .to_string();

        Some(SentryEnvelope {
            level: entry.level.clone(),
            message,
            tags,
        })
    } else {
        None
    };

    ExportEnvelope { posthog, sentry }
}

fn insert_tag_from_props(
    tags: &mut BTreeMap<String, String>,
    props: &Map<String, Value>,
    key: &str,
) {
    if let Some(value) = props.get(key).and_then(|v| v.as_str()) {
        tags.insert(key.to_string(), value.to_string());
    }
}

fn build_posthog_properties(
    entry: &LogEntry,
    mode: ObservabilityMode,
    environment: &str,
) -> Map<String, Value> {
    match mode {
        ObservabilityMode::DevVerbose => build_dev_properties(entry, environment),
        ObservabilityMode::ProdMetadataOnly => build_prod_properties(entry, environment),
    }
}

fn build_dev_properties(entry: &LogEntry, environment: &str) -> Map<String, Value> {
    let mut props = Map::new();
    let runtime = runtime_from_entry(entry);
    props.insert(
        "timestamp".to_string(),
        Value::String(entry.timestamp.clone()),
    );
    props.insert("runtime".to_string(), Value::String(runtime));
    props.insert("service".to_string(), Value::String(entry.service.clone()));
    props.insert(
        "component".to_string(),
        Value::String(component_from_entry(entry)),
    );
    props.insert("level".to_string(), Value::String(entry.level.clone()));
    props.insert("target".to_string(), Value::String(entry.target.clone()));
    props.insert(
        "event_code".to_string(),
        Value::String(event_code_from_entry(entry)),
    );
    props.insert("message".to_string(), Value::String(entry.message.clone()));
    props.insert(
        "message_hash".to_string(),
        Value::String(sha256_prefixed(&entry.message)),
    );
    props.insert(
        "environment".to_string(),
        Value::String(environment.to_string()),
    );
    props.insert("pid".to_string(), Value::Number(entry.pid.into()));

    let sanitized_fields = sanitize_object(&entry.fields);
    if !sanitized_fields.is_empty() {
        props.insert("fields".to_string(), Value::Object(sanitized_fields));
    }

    let correlation_fields = extract_correlation_fields(&entry.fields);
    insert_correlation_fields(&mut props, &correlation_fields);

    props
}

fn build_prod_properties(entry: &LogEntry, environment: &str) -> Map<String, Value> {
    let mut props = Map::new();
    let runtime = runtime_from_entry(entry);
    props.insert(
        "timestamp".to_string(),
        Value::String(entry.timestamp.clone()),
    );
    props.insert("runtime".to_string(), Value::String(runtime));
    props.insert("service".to_string(), Value::String(entry.service.clone()));
    props.insert(
        "component".to_string(),
        Value::String(component_from_entry(entry)),
    );
    props.insert("level".to_string(), Value::String(entry.level.clone()));
    props.insert(
        "event_code".to_string(),
        Value::String(event_code_from_entry(entry)),
    );
    props.insert(
        "environment".to_string(),
        Value::String(environment.to_string()),
    );
    props.insert(
        "message_hash".to_string(),
        Value::String(sha256_prefixed(&entry.message)),
    );

    for key in PROD_ALLOWED_FIELDS {
        if let Some(value) = entry.fields.get(key) {
            let sanitized = sanitize_value(key, value);
            if !sanitized.is_null() {
                props.insert(key.to_string(), sanitized);
            }
        }
    }

    let correlation_fields = extract_correlation_fields(&entry.fields);
    insert_correlation_fields(&mut props, &correlation_fields);

    props
}

fn sanitize_object(fields: &HashMap<String, Value>) -> Map<String, Value> {
    let mut out = Map::new();
    for (k, v) in fields {
        out.insert(k.clone(), sanitize_value(k, v));
    }
    out
}

fn sanitize_value(key: &str, value: &Value) -> Value {
    if is_sensitive_key(key) {
        return Value::String("[REDACTED]".to_string());
    }

    match value {
        Value::String(s) => sanitize_string(s),
        Value::Object(map) => {
            let mut out = Map::new();
            for (k, v) in map {
                out.insert(k.clone(), sanitize_value(k, v));
            }
            Value::Object(out)
        }
        Value::Array(items) => Value::Array(
            items
                .iter()
                .map(|item| sanitize_value(key, item))
                .collect::<Vec<_>>(),
        ),
        _ => value.clone(),
    }
}

fn sanitize_string(raw: &str) -> Value {
    if looks_like_sensitive_value(raw) {
        return Value::String("[REDACTED]".to_string());
    }
    if raw.len() > 512 {
        return Value::String(format!("[TRUNCATED:{}]", sha256_prefixed(raw)));
    }
    Value::String(raw.to_string())
}

fn looks_like_sensitive_value(raw: &str) -> bool {
    let lower = raw.to_ascii_lowercase();
    if lower.starts_with("bearer ") {
        return true;
    }
    if raw.matches('.').count() == 2 && raw.len() > 40 {
        return true;
    }
    is_long_hex(raw) || is_long_base64(raw)
}

fn is_sensitive_key(key: &str) -> bool {
    let lower = key.to_ascii_lowercase();
    DENYLIST_KEYS.iter().any(|entry| lower.contains(entry))
}

fn is_long_hex(value: &str) -> bool {
    value.len() > 48 && value.chars().all(|c| c.is_ascii_hexdigit())
}

fn is_long_base64(value: &str) -> bool {
    value.len() > 48
        && value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '+' || c == '/' || c == '=' || c == '_')
}

fn read_string_field(fields: &HashMap<String, Value>, key: &str) -> Option<String> {
    fields.get(key).and_then(|v| match v {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        Value::Bool(b) => Some(b.to_string()),
        _ => None,
    })
}

fn read_first_string_field(fields: &HashMap<String, Value>, keys: &[&str]) -> Option<String> {
    for key in keys {
        if let Some(value) = read_string_field(fields, key) {
            return Some(value);
        }
    }
    None
}

fn sanitize_correlation_string(value: String) -> String {
    match sanitize_string(&value) {
        Value::String(sanitized) => sanitized,
        _ => value,
    }
}

fn normalize_hash_identifier(value: String) -> String {
    if value.to_ascii_lowercase().starts_with("sha256:") {
        return value;
    }
    sha256_prefixed(&value)
}

fn extract_correlation_fields(fields: &HashMap<String, Value>) -> CorrelationFields {
    CorrelationFields {
        request_id: read_first_string_field(fields, &["request_id", "requestId", "request-id"])
            .map(sanitize_correlation_string),
        session_id: read_first_string_field(fields, &["session_id", "sessionId"])
            .map(sanitize_correlation_string),
        device_id_hash: read_first_string_field(fields, &["device_id_hash", "deviceIdHash"])
            .map(normalize_hash_identifier)
            .or_else(|| {
                read_first_string_field(fields, &["device_id", "deviceId"])
                    .map(|raw| sha256_prefixed(&raw))
            }),
        user_id_hash: read_first_string_field(fields, &["user_id_hash", "userIdHash"])
            .map(normalize_hash_identifier)
            .or_else(|| {
                read_first_string_field(fields, &["user_id", "userId"])
                    .map(|raw| sha256_prefixed(&raw))
            }),
        trace_id: read_first_string_field(fields, &["trace_id", "traceId"])
            .map(sanitize_correlation_string),
        span_id: read_first_string_field(fields, &["span_id", "spanId"])
            .map(sanitize_correlation_string),
    }
}

fn insert_correlation_fields(props: &mut Map<String, Value>, fields: &CorrelationFields) {
    if let Some(value) = &fields.request_id {
        props.insert("request_id".to_string(), Value::String(value.clone()));
    }
    if let Some(value) = &fields.session_id {
        props.insert("session_id".to_string(), Value::String(value.clone()));
    }
    if let Some(value) = &fields.device_id_hash {
        props.insert("device_id_hash".to_string(), Value::String(value.clone()));
    }
    if let Some(value) = &fields.user_id_hash {
        props.insert("user_id_hash".to_string(), Value::String(value.clone()));
    }
    if let Some(value) = &fields.trace_id {
        props.insert("trace_id".to_string(), Value::String(value.clone()));
    }
    if let Some(value) = &fields.span_id {
        props.insert("span_id".to_string(), Value::String(value.clone()));
    }
}

fn event_code_from_entry(entry: &LogEntry) -> String {
    read_string_field(&entry.fields, "event_code").unwrap_or_else(|| {
        let target = entry
            .target
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() { c } else { '.' })
            .collect::<String>()
            .trim_matches('.')
            .to_string();
        format!("{}.{}", entry.service, target)
    })
}

fn component_from_entry(entry: &LogEntry) -> String {
    read_string_field(&entry.fields, "component").unwrap_or_else(|| {
        entry
            .target
            .split("::")
            .next()
            .map(|s| s.to_string())
            .unwrap_or_else(|| "unknown".to_string())
    })
}

fn runtime_from_entry(entry: &LogEntry) -> String {
    read_string_field(&entry.fields, "runtime").unwrap_or_else(|| entry.service.clone())
}

fn should_sample(entry: &LogEntry, sampling: &SamplingConfig) -> bool {
    let rate = match entry.level.as_str() {
        "DEBUG" | "TRACE" => sampling.debug_rate,
        "INFO" | "NOTICE" => sampling.info_rate,
        "WARN" => sampling.warn_rate,
        "ERROR" => sampling.error_rate,
        _ => 1.0,
    }
    .clamp(0.0, 1.0);

    if rate >= 1.0 {
        return true;
    }
    if rate <= 0.0 {
        return false;
    }

    let key = format!(
        "{}:{}:{}:{}",
        entry.service, entry.target, entry.message, entry.timestamp
    );
    let digest = Sha256::digest(key.as_bytes());
    let mut bytes = [0_u8; 8];
    bytes.copy_from_slice(&digest[..8]);
    let value = u64::from_be_bytes(bytes);
    (value as f64 / u64::MAX as f64) < rate
}

fn sha256_prefixed(value: &str) -> String {
    let digest = Sha256::digest(value.as_bytes());
    format!("sha256:{}", hex::encode(digest))
}

fn now_rfc3339_fallback() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    format!("{secs}")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_entry(level: &str, message: &str) -> LogEntry {
        let mut fields = HashMap::new();
        fields.insert("request_id".to_string(), Value::String("req_1".to_string()));
        fields.insert(
            "access_token".to_string(),
            Value::String("secret-token".to_string()),
        );
        fields.insert(
            "device_id".to_string(),
            Value::String("dev-123".to_string()),
        );
        fields.insert("user_id".to_string(), Value::String("usr-456".to_string()));

        LogEntry {
            timestamp: "2026-02-13T08:00:00.000Z".to_string(),
            level: level.to_string(),
            service: "daemon".to_string(),
            pid: 111,
            target: "daemon::auth".to_string(),
            message: message.to_string(),
            fields,
            span: None,
            file: None,
            line: None,
        }
    }

    #[test]
    fn prod_mode_strips_raw_payload_and_message() {
        let entry = sample_entry("ERROR", "token refresh failed");
        let props =
            build_posthog_properties(&entry, ObservabilityMode::ProdMetadataOnly, "production");

        assert!(props.get("message").is_none());
        assert!(props.get("fields").is_none());
        assert!(props.get("access_token").is_none());
        assert!(props.get("message_hash").is_some());
        assert!(props.get("device_id_hash").is_some());
        assert!(props.get("user_id_hash").is_some());
    }

    #[test]
    fn dev_mode_redacts_sensitive_keys() {
        let entry = sample_entry("INFO", "hello");
        let props = build_posthog_properties(&entry, ObservabilityMode::DevVerbose, "development");
        let fields = props.get("fields").and_then(|v| v.as_object()).unwrap();
        assert_eq!(
            fields.get("access_token"),
            Some(&Value::String("[REDACTED]".to_string()))
        );
    }

    #[test]
    fn sampling_is_deterministic_for_same_entry() {
        let entry = sample_entry("INFO", "stable-message");
        let sampling = SamplingConfig {
            debug_rate: 0.0,
            info_rate: 0.5,
            warn_rate: 1.0,
            error_rate: 1.0,
        };

        let first = should_sample(&entry, &sampling);
        let second = should_sample(&entry, &sampling);
        assert_eq!(first, second);
    }

    #[test]
    fn prod_mode_canonicalizes_correlation_aliases_and_hashes_raw_ids() {
        let mut entry = sample_entry("ERROR", "upstream request failed");
        entry.fields.remove("request_id");
        entry.fields.remove("device_id");
        entry.fields.remove("user_id");
        entry.fields.insert(
            "requestId".to_string(),
            Value::String("req_alias".to_string()),
        );
        entry.fields.insert(
            "sessionId".to_string(),
            Value::String("session_alias".to_string()),
        );
        entry.fields.insert(
            "traceId".to_string(),
            Value::String("trace_alias".to_string()),
        );
        entry.fields.insert(
            "spanId".to_string(),
            Value::String("span_alias".to_string()),
        );
        entry.fields.insert(
            "deviceId".to_string(),
            Value::String("device_alias".to_string()),
        );
        entry.fields.insert(
            "userId".to_string(),
            Value::String("user_alias".to_string()),
        );

        let props =
            build_posthog_properties(&entry, ObservabilityMode::ProdMetadataOnly, "production");

        assert_eq!(
            props.get("request_id"),
            Some(&Value::String("req_alias".to_string()))
        );
        assert_eq!(
            props.get("session_id"),
            Some(&Value::String("session_alias".to_string()))
        );
        assert_eq!(
            props.get("trace_id"),
            Some(&Value::String("trace_alias".to_string()))
        );
        assert_eq!(
            props.get("span_id"),
            Some(&Value::String("span_alias".to_string()))
        );
        assert_eq!(
            props.get("device_id_hash"),
            Some(&Value::String(sha256_prefixed("device_alias")))
        );
        assert_eq!(
            props.get("user_id_hash"),
            Some(&Value::String(sha256_prefixed("user_alias")))
        );
    }

    #[test]
    fn sentry_tags_include_trace_and_span_correlation_keys() {
        let mut entry = sample_entry("ERROR", "failed");
        entry
            .fields
            .insert("trace_id".to_string(), Value::String("trace-1".to_string()));
        entry
            .fields
            .insert("span_id".to_string(), Value::String("span-1".to_string()));

        let envelope = build_export_envelope(&entry, ObservabilityMode::ProdMetadataOnly, "prod");
        let sentry = envelope.sentry.expect("expected sentry envelope for ERROR");

        assert_eq!(sentry.tags.get("trace_id"), Some(&"trace-1".to_string()));
        assert_eq!(sentry.tags.get("span_id"), Some(&"span-1".to_string()));
    }
}
