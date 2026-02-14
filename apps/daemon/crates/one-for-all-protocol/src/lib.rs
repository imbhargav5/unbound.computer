//! Pure IPC protocol types for the Unbound daemon.
//!
//! This crate contains only data types and serialization — no I/O, no async,
//! no transport. It defines the shared language between client and server.

use serde::{Deserialize, Serialize};

/// IPC method types.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Method {
    // Health
    Health,
    Shutdown,

    // Authentication
    #[serde(rename = "auth.status")]
    AuthStatus,
    #[serde(rename = "auth.login")]
    AuthLogin,
    #[serde(rename = "auth.complete_social")]
    AuthCompleteSocial,
    #[serde(rename = "auth.logout")]
    AuthLogout,

    // Billing
    #[serde(rename = "billing.usage_status")]
    BillingUsageStatus,

    // Sessions
    #[serde(rename = "session.list")]
    SessionList,
    #[serde(rename = "session.create")]
    SessionCreate,
    #[serde(rename = "session.get")]
    SessionGet,
    #[serde(rename = "session.delete")]
    SessionDelete,

    // Messages
    #[serde(rename = "message.list")]
    MessageList,
    #[serde(rename = "message.send")]
    MessageSend,

    // Outbox
    #[serde(rename = "outbox.status")]
    OutboxStatus,

    // Repositories
    #[serde(rename = "repository.list")]
    RepositoryList,
    #[serde(rename = "repository.add")]
    RepositoryAdd,
    #[serde(rename = "repository.remove")]
    RepositoryRemove,
    #[serde(rename = "repository.get_settings")]
    RepositoryGetSettings,
    #[serde(rename = "repository.update_settings")]
    RepositoryUpdateSettings,
    #[serde(rename = "repository.list_files")]
    RepositoryListFiles,
    #[serde(rename = "repository.read_file")]
    RepositoryReadFile,
    #[serde(rename = "repository.read_file_slice")]
    RepositoryReadFileSlice,
    #[serde(rename = "repository.write_file")]
    RepositoryWriteFile,
    #[serde(rename = "repository.replace_file_range")]
    RepositoryReplaceFileRange,

    // Claude CLI
    #[serde(rename = "claude.send")]
    ClaudeSend,
    #[serde(rename = "claude.status")]
    ClaudeStatus,
    #[serde(rename = "claude.stop")]
    ClaudeStop,

    // Subscriptions (streaming)
    #[serde(rename = "session.subscribe")]
    SessionSubscribe,
    #[serde(rename = "session.unsubscribe")]
    SessionUnsubscribe,

    // Git operations
    #[serde(rename = "git.status")]
    GitStatus,
    #[serde(rename = "git.diff_file")]
    GitDiffFile,
    #[serde(rename = "git.log")]
    GitLog,
    #[serde(rename = "git.branches")]
    GitBranches,
    #[serde(rename = "git.stage")]
    GitStage,
    #[serde(rename = "git.unstage")]
    GitUnstage,
    #[serde(rename = "git.discard")]
    GitDiscard,
    #[serde(rename = "git.commit")]
    GitCommitChanges,
    #[serde(rename = "git.push")]
    GitPush,

    // GitHub CLI operations
    #[serde(rename = "gh.auth_status")]
    GhAuthStatus,
    #[serde(rename = "gh.pr_create")]
    GhPrCreate,
    #[serde(rename = "gh.pr_view")]
    GhPrView,
    #[serde(rename = "gh.pr_list")]
    GhPrList,
    #[serde(rename = "gh.pr_checks")]
    GhPrChecks,
    #[serde(rename = "gh.pr_merge")]
    GhPrMerge,

    // System operations
    #[serde(rename = "system.check_dependencies")]
    SystemCheckDependencies,
    #[serde(rename = "system.refresh_capabilities")]
    SystemRefreshCapabilities,

    // Terminal operations
    #[serde(rename = "terminal.run")]
    TerminalRun,
    #[serde(rename = "terminal.status")]
    TerminalStatus,
    #[serde(rename = "terminal.stop")]
    TerminalStop,
}

/// Server-push event for subscriptions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Event {
    /// Event type (e.g., "message", "status_change").
    #[serde(rename = "type")]
    pub event_type: EventType,
    /// Session ID this event relates to.
    pub session_id: String,
    /// Event payload.
    pub data: serde_json::Value,
    /// Sequence number for ordering/resumption.
    pub sequence: i64,
}

/// Types of events that can be pushed to subscribers.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EventType {
    /// New message added to session.
    Message,
    /// Streaming content chunk (not stored, for real-time display).
    StreamingChunk,
    /// Claude status changed (started/stopped).
    StatusChange,
    /// Initial state dump on subscribe.
    InitialState,
    /// Keepalive ping.
    Ping,
    /// Terminal output chunk (stdout or stderr).
    TerminalOutput,
    /// Terminal command finished with exit code.
    TerminalFinished,
    /// Raw Claude NDJSON event (TUI parses typed messages from this).
    ClaudeEvent,
    /// Authentication state changed.
    AuthStateChanged,
    /// A new session was created.
    SessionCreated,
    /// A session was deleted.
    SessionDeleted,
}

impl Event {
    /// Create a new event.
    pub fn new(
        event_type: EventType,
        session_id: &str,
        data: serde_json::Value,
        sequence: i64,
    ) -> Self {
        Self {
            event_type,
            session_id: session_id.to_string(),
            data,
            sequence,
        }
    }

    /// Serialize to JSON string.
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }

    /// Deserialize from JSON string.
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }
}

/// IPC request message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Request {
    /// Request ID for correlation.
    pub id: String,
    /// Method to invoke.
    pub method: Method,
    /// Method parameters (optional).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub params: Option<serde_json::Value>,
}

impl Request {
    /// Create a new request with auto-generated ID.
    pub fn new(method: Method) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            method,
            params: None,
        }
    }

    /// Create a new request with parameters.
    pub fn with_params(method: Method, params: serde_json::Value) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            method,
            params: Some(params),
        }
    }

    /// Create a request with a specific ID (useful for tests).
    pub fn with_id(id: &str, method: Method) -> Self {
        Self {
            id: id.to_string(),
            method,
            params: None,
        }
    }

    /// Serialize to JSON string.
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }

    /// Deserialize from JSON string.
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }
}

/// IPC response message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Response {
    /// Request ID for correlation.
    pub id: String,
    /// Result data (if successful).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    /// Error information (if failed).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<ErrorInfo>,
}

/// Error information in a response.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorInfo {
    /// Error code.
    pub code: i32,
    /// Error message.
    pub message: String,
    /// Additional error data.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<serde_json::Value>,
}

impl Response {
    /// Create a successful response.
    pub fn success(id: &str, result: serde_json::Value) -> Self {
        Self {
            id: id.to_string(),
            result: Some(result),
            error: None,
        }
    }

    /// Create an error response.
    pub fn error(id: &str, code: i32, message: &str) -> Self {
        Self {
            id: id.to_string(),
            result: None,
            error: Some(ErrorInfo {
                code,
                message: message.to_string(),
                data: None,
            }),
        }
    }

    /// Create an error response with additional data.
    pub fn error_with_data(id: &str, code: i32, message: &str, data: serde_json::Value) -> Self {
        Self {
            id: id.to_string(),
            result: None,
            error: Some(ErrorInfo {
                code,
                message: message.to_string(),
                data: Some(data),
            }),
        }
    }

    /// Serialize to JSON string.
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }

    /// Deserialize from JSON string.
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }

    /// Check if the response is successful.
    pub fn is_success(&self) -> bool {
        self.error.is_none()
    }
}

/// Standard JSON-RPC error codes.
pub mod error_codes {
    pub const PARSE_ERROR: i32 = -32700;
    pub const INVALID_REQUEST: i32 = -32600;
    pub const METHOD_NOT_FOUND: i32 = -32601;
    pub const INVALID_PARAMS: i32 = -32602;
    pub const INTERNAL_ERROR: i32 = -32603;
    pub const NOT_AUTHENTICATED: i32 = -32001;
    pub const NOT_FOUND: i32 = -32002;
    pub const CONFLICT: i32 = -32003;
}

#[cfg(test)]
mod tests {
    use super::*;

    // =========================================================================
    // Method serialization tests
    // =========================================================================

    #[test]
    fn method_health_serializes_to_snake_case() {
        let json = serde_json::to_string(&Method::Health).unwrap();
        assert_eq!(json, "\"health\"");
    }

    #[test]
    fn method_shutdown_serializes_to_snake_case() {
        let json = serde_json::to_string(&Method::Shutdown).unwrap();
        assert_eq!(json, "\"shutdown\"");
    }

    #[test]
    fn method_dotted_names_serialize_correctly() {
        let cases = vec![
            (Method::AuthStatus, "\"auth.status\""),
            (Method::AuthLogin, "\"auth.login\""),
            (Method::AuthCompleteSocial, "\"auth.complete_social\""),
            (Method::AuthLogout, "\"auth.logout\""),
            (Method::BillingUsageStatus, "\"billing.usage_status\""),
            (Method::SessionList, "\"session.list\""),
            (Method::SessionCreate, "\"session.create\""),
            (Method::SessionGet, "\"session.get\""),
            (Method::SessionDelete, "\"session.delete\""),
            (Method::MessageList, "\"message.list\""),
            (Method::MessageSend, "\"message.send\""),
            (Method::OutboxStatus, "\"outbox.status\""),
            (Method::RepositoryList, "\"repository.list\""),
            (Method::RepositoryAdd, "\"repository.add\""),
            (Method::RepositoryRemove, "\"repository.remove\""),
            (Method::RepositoryGetSettings, "\"repository.get_settings\""),
            (
                Method::RepositoryUpdateSettings,
                "\"repository.update_settings\"",
            ),
            (Method::RepositoryListFiles, "\"repository.list_files\""),
            (Method::RepositoryReadFile, "\"repository.read_file\""),
            (
                Method::RepositoryReadFileSlice,
                "\"repository.read_file_slice\"",
            ),
            (Method::RepositoryWriteFile, "\"repository.write_file\""),
            (
                Method::RepositoryReplaceFileRange,
                "\"repository.replace_file_range\"",
            ),
            (Method::ClaudeSend, "\"claude.send\""),
            (Method::ClaudeStatus, "\"claude.status\""),
            (Method::ClaudeStop, "\"claude.stop\""),
            (Method::SessionSubscribe, "\"session.subscribe\""),
            (Method::SessionUnsubscribe, "\"session.unsubscribe\""),
            (Method::GitStatus, "\"git.status\""),
            (Method::GitDiffFile, "\"git.diff_file\""),
            (Method::GitLog, "\"git.log\""),
            (Method::GitBranches, "\"git.branches\""),
            (Method::GitStage, "\"git.stage\""),
            (Method::GitUnstage, "\"git.unstage\""),
            (Method::GitDiscard, "\"git.discard\""),
            (Method::GitCommitChanges, "\"git.commit\""),
            (Method::GitPush, "\"git.push\""),
            (Method::GhAuthStatus, "\"gh.auth_status\""),
            (Method::GhPrCreate, "\"gh.pr_create\""),
            (Method::GhPrView, "\"gh.pr_view\""),
            (Method::GhPrList, "\"gh.pr_list\""),
            (Method::GhPrChecks, "\"gh.pr_checks\""),
            (Method::GhPrMerge, "\"gh.pr_merge\""),
            (
                Method::SystemCheckDependencies,
                "\"system.check_dependencies\"",
            ),
            (
                Method::SystemRefreshCapabilities,
                "\"system.refresh_capabilities\"",
            ),
            (Method::TerminalRun, "\"terminal.run\""),
            (Method::TerminalStatus, "\"terminal.status\""),
            (Method::TerminalStop, "\"terminal.stop\""),
        ];

        for (method, expected) in cases {
            let json = serde_json::to_string(&method).unwrap();
            assert_eq!(json, expected, "Method {:?} serialized incorrectly", method);
        }
    }

    #[test]
    fn method_roundtrip_all_variants() {
        let methods = vec![
            Method::Health,
            Method::Shutdown,
            Method::AuthStatus,
            Method::AuthLogin,
            Method::AuthCompleteSocial,
            Method::AuthLogout,
            Method::BillingUsageStatus,
            Method::SessionList,
            Method::SessionCreate,
            Method::SessionGet,
            Method::SessionDelete,
            Method::MessageList,
            Method::MessageSend,
            Method::OutboxStatus,
            Method::RepositoryList,
            Method::RepositoryAdd,
            Method::RepositoryRemove,
            Method::RepositoryGetSettings,
            Method::RepositoryUpdateSettings,
            Method::RepositoryListFiles,
            Method::RepositoryReadFile,
            Method::RepositoryReadFileSlice,
            Method::RepositoryWriteFile,
            Method::RepositoryReplaceFileRange,
            Method::ClaudeSend,
            Method::ClaudeStatus,
            Method::ClaudeStop,
            Method::SessionSubscribe,
            Method::SessionUnsubscribe,
            Method::GitStatus,
            Method::GitDiffFile,
            Method::GitLog,
            Method::GitBranches,
            Method::GitStage,
            Method::GitUnstage,
            Method::GitDiscard,
            Method::GitCommitChanges,
            Method::GitPush,
            Method::GhAuthStatus,
            Method::GhPrCreate,
            Method::GhPrView,
            Method::GhPrList,
            Method::GhPrChecks,
            Method::GhPrMerge,
            Method::SystemCheckDependencies,
            Method::SystemRefreshCapabilities,
            Method::TerminalRun,
            Method::TerminalStatus,
            Method::TerminalStop,
        ];

        for method in methods {
            let json = serde_json::to_string(&method).unwrap();
            let roundtripped: Method = serde_json::from_str(&json).unwrap();
            assert_eq!(method, roundtripped, "Roundtrip failed for {:?}", method);
        }
    }

    #[test]
    fn method_deserialization_rejects_unknown() {
        let result: Result<Method, _> = serde_json::from_str("\"not.a.method\"");
        assert!(result.is_err());
    }

    #[test]
    fn method_eq_and_hash() {
        use std::collections::HashSet;
        let mut set = HashSet::new();
        set.insert(Method::Health);
        set.insert(Method::Health);
        assert_eq!(set.len(), 1);
        set.insert(Method::Shutdown);
        assert_eq!(set.len(), 2);
    }

    #[test]
    fn method_clone() {
        let m = Method::ClaudeSend;
        let m2 = m.clone();
        assert_eq!(m, m2);
    }

    // =========================================================================
    // Request tests
    // =========================================================================

    #[test]
    fn request_new_generates_unique_ids() {
        let r1 = Request::new(Method::Health);
        let r2 = Request::new(Method::Health);
        assert_ne!(r1.id, r2.id);
        assert!(!r1.id.is_empty());
    }

    #[test]
    fn request_new_has_no_params() {
        let r = Request::new(Method::Health);
        assert!(r.params.is_none());
    }

    #[test]
    fn request_with_params_stores_params() {
        let r = Request::with_params(
            Method::SessionCreate,
            serde_json::json!({"repository_id": "abc"}),
        );
        assert!(r.params.is_some());
        assert_eq!(r.params.as_ref().unwrap()["repository_id"], "abc");
    }

    #[test]
    fn request_with_id_uses_given_id() {
        let r = Request::with_id("test-123", Method::Health);
        assert_eq!(r.id, "test-123");
    }

    #[test]
    fn request_serialization_roundtrip() {
        let request = Request::with_params(
            Method::SessionCreate,
            serde_json::json!({"title": "my session"}),
        );
        let json = request.to_json().unwrap();
        let parsed = Request::from_json(&json).unwrap();
        assert_eq!(request.id, parsed.id);
        assert_eq!(request.method, parsed.method);
        assert_eq!(request.params, parsed.params);
    }

    #[test]
    fn request_serialization_omits_none_params() {
        let request = Request::new(Method::Health);
        let json = request.to_json().unwrap();
        assert!(!json.contains("params"));
    }

    #[test]
    fn request_serialization_includes_method() {
        let request = Request::new(Method::AuthLogin);
        let json = request.to_json().unwrap();
        assert!(json.contains("\"method\":\"auth.login\""));
    }

    #[test]
    fn request_deserialization_rejects_invalid_json() {
        assert!(Request::from_json("not json").is_err());
    }

    #[test]
    fn request_deserialization_rejects_missing_method() {
        assert!(Request::from_json(r#"{"id":"123"}"#).is_err());
    }

    #[test]
    fn request_deserialization_rejects_unknown_method() {
        assert!(Request::from_json(r#"{"id":"123","method":"invalid.method"}"#).is_err());
    }

    #[test]
    fn request_deserialization_accepts_no_params() {
        let r = Request::from_json(r#"{"id":"abc","method":"health"}"#).unwrap();
        assert_eq!(r.id, "abc");
        assert_eq!(r.method, Method::Health);
        assert!(r.params.is_none());
    }

    #[test]
    fn request_deserialization_accepts_params() {
        let json = r#"{"id":"abc","method":"session.create","params":{"title":"test"}}"#;
        let r = Request::from_json(json).unwrap();
        assert_eq!(r.method, Method::SessionCreate);
        assert_eq!(r.params.unwrap()["title"], "test");
    }

    // =========================================================================
    // Response tests
    // =========================================================================

    #[test]
    fn response_success_is_success() {
        let r = Response::success("1", serde_json::json!({}));
        assert!(r.is_success());
        assert!(r.result.is_some());
        assert!(r.error.is_none());
    }

    #[test]
    fn response_error_is_not_success() {
        let r = Response::error("1", error_codes::INTERNAL_ERROR, "boom");
        assert!(!r.is_success());
        assert!(r.result.is_none());
        assert!(r.error.is_some());
    }

    #[test]
    fn response_success_serialization_omits_error() {
        let r = Response::success("1", serde_json::json!({"key": "value"}));
        let json = r.to_json().unwrap();
        assert!(!json.contains("\"error\""));
        assert!(json.contains("\"key\":\"value\""));
    }

    #[test]
    fn response_error_serialization_omits_result() {
        let r = Response::error("1", error_codes::NOT_FOUND, "not found");
        let json = r.to_json().unwrap();
        assert!(!json.contains("\"result\""));
        assert!(json.contains("\"code\":-32002"));
        assert!(json.contains("\"message\":\"not found\""));
    }

    #[test]
    fn response_error_with_data_includes_data() {
        let r = Response::error_with_data(
            "1",
            error_codes::INVALID_PARAMS,
            "bad params",
            serde_json::json!({"field": "name"}),
        );
        let json = r.to_json().unwrap();
        assert!(json.contains("\"field\":\"name\""));
    }

    #[test]
    fn response_serialization_roundtrip_success() {
        let r = Response::success("test-id", serde_json::json!({"data": [1, 2, 3]}));
        let json = r.to_json().unwrap();
        let parsed = Response::from_json(&json).unwrap();
        assert_eq!(parsed.id, "test-id");
        assert!(parsed.is_success());
        assert_eq!(parsed.result.unwrap()["data"], serde_json::json!([1, 2, 3]));
    }

    #[test]
    fn response_serialization_roundtrip_error() {
        let r = Response::error("err-1", error_codes::INTERNAL_ERROR, "something broke");
        let json = r.to_json().unwrap();
        let parsed = Response::from_json(&json).unwrap();
        assert_eq!(parsed.id, "err-1");
        assert!(!parsed.is_success());
        let err = parsed.error.unwrap();
        assert_eq!(err.code, error_codes::INTERNAL_ERROR);
        assert_eq!(err.message, "something broke");
    }

    #[test]
    fn response_deserialization_rejects_invalid_json() {
        assert!(Response::from_json("garbage").is_err());
    }

    // =========================================================================
    // ErrorInfo tests
    // =========================================================================

    #[test]
    fn error_info_serialization() {
        let e = ErrorInfo {
            code: -32603,
            message: "internal".to_string(),
            data: Some(serde_json::json!({"detail": "x"})),
        };
        let json = serde_json::to_string(&e).unwrap();
        assert!(json.contains("\"code\":-32603"));
        assert!(json.contains("\"detail\":\"x\""));
    }

    #[test]
    fn error_info_without_data_omits_data_field() {
        let e = ErrorInfo {
            code: -32601,
            message: "not found".to_string(),
            data: None,
        };
        let json = serde_json::to_string(&e).unwrap();
        assert!(!json.contains("\"data\""));
    }

    // =========================================================================
    // Event tests
    // =========================================================================

    #[test]
    fn event_new_stores_all_fields() {
        let e = Event::new(
            EventType::Message,
            "session-1",
            serde_json::json!({"content": "hello"}),
            42,
        );
        assert_eq!(e.event_type, EventType::Message);
        assert_eq!(e.session_id, "session-1");
        assert_eq!(e.sequence, 42);
        assert_eq!(e.data["content"], "hello");
    }

    #[test]
    fn event_serialization_roundtrip() {
        let e = Event::new(
            EventType::ClaudeEvent,
            "sess-abc",
            serde_json::json!({"raw": "data"}),
            100,
        );
        let json = e.to_json().unwrap();
        let parsed = Event::from_json(&json).unwrap();
        assert_eq!(parsed.event_type, EventType::ClaudeEvent);
        assert_eq!(parsed.session_id, "sess-abc");
        assert_eq!(parsed.sequence, 100);
    }

    #[test]
    fn event_type_serializes_to_snake_case() {
        let types = vec![
            (EventType::Message, "\"message\""),
            (EventType::StreamingChunk, "\"streaming_chunk\""),
            (EventType::StatusChange, "\"status_change\""),
            (EventType::InitialState, "\"initial_state\""),
            (EventType::Ping, "\"ping\""),
            (EventType::TerminalOutput, "\"terminal_output\""),
            (EventType::TerminalFinished, "\"terminal_finished\""),
            (EventType::ClaudeEvent, "\"claude_event\""),
            (EventType::AuthStateChanged, "\"auth_state_changed\""),
            (EventType::SessionCreated, "\"session_created\""),
            (EventType::SessionDeleted, "\"session_deleted\""),
        ];

        for (event_type, expected) in types {
            let json = serde_json::to_string(&event_type).unwrap();
            assert_eq!(
                json, expected,
                "EventType {:?} serialized incorrectly",
                event_type
            );
        }
    }

    #[test]
    fn event_type_roundtrip_all_variants() {
        let types = vec![
            EventType::Message,
            EventType::StreamingChunk,
            EventType::StatusChange,
            EventType::InitialState,
            EventType::Ping,
            EventType::TerminalOutput,
            EventType::TerminalFinished,
            EventType::ClaudeEvent,
            EventType::AuthStateChanged,
            EventType::SessionCreated,
            EventType::SessionDeleted,
        ];
        for et in types {
            let json = serde_json::to_string(&et).unwrap();
            let parsed: EventType = serde_json::from_str(&json).unwrap();
            assert_eq!(et, parsed);
        }
    }

    #[test]
    fn event_deserialization_rejects_invalid_json() {
        assert!(Event::from_json("not an event").is_err());
    }

    #[test]
    fn event_uses_type_field_name() {
        let e = Event::new(EventType::Ping, "s1", serde_json::json!({}), 0);
        let json = e.to_json().unwrap();
        assert!(json.contains("\"type\":\"ping\""));
        assert!(!json.contains("\"event_type\""));
    }

    #[test]
    fn event_sequence_can_be_negative() {
        let e = Event::new(EventType::Message, "s1", serde_json::json!({}), -1);
        let json = e.to_json().unwrap();
        let parsed = Event::from_json(&json).unwrap();
        assert_eq!(parsed.sequence, -1);
    }

    #[test]
    fn event_sequence_can_be_zero() {
        let e = Event::new(EventType::Message, "s1", serde_json::json!({}), 0);
        assert_eq!(e.sequence, 0);
    }

    #[test]
    fn event_data_can_be_complex_json() {
        let data = serde_json::json!({
            "messages": [
                {"id": 1, "content": "hello"},
                {"id": 2, "content": "world"}
            ],
            "metadata": {"count": 2}
        });
        let e = Event::new(EventType::InitialState, "s1", data.clone(), 0);
        let json = e.to_json().unwrap();
        let parsed = Event::from_json(&json).unwrap();
        assert_eq!(parsed.data, data);
    }

    // =========================================================================
    // Error codes tests
    // =========================================================================

    #[test]
    fn error_codes_are_json_rpc_standard() {
        assert_eq!(error_codes::PARSE_ERROR, -32700);
        assert_eq!(error_codes::INVALID_REQUEST, -32600);
        assert_eq!(error_codes::METHOD_NOT_FOUND, -32601);
        assert_eq!(error_codes::INVALID_PARAMS, -32602);
        assert_eq!(error_codes::INTERNAL_ERROR, -32603);
    }

    #[test]
    fn error_codes_custom_are_in_custom_range() {
        assert_eq!(error_codes::NOT_AUTHENTICATED, -32001);
        assert_eq!(error_codes::NOT_FOUND, -32002);
        assert_eq!(error_codes::CONFLICT, -32003);
    }

    #[test]
    fn error_codes_all_negative() {
        let codes = [
            error_codes::PARSE_ERROR,
            error_codes::INVALID_REQUEST,
            error_codes::METHOD_NOT_FOUND,
            error_codes::INVALID_PARAMS,
            error_codes::INTERNAL_ERROR,
            error_codes::NOT_AUTHENTICATED,
            error_codes::NOT_FOUND,
            error_codes::CONFLICT,
        ];
        for code in codes {
            assert!(code < 0, "Error code {} should be negative", code);
        }
    }

    #[test]
    fn error_codes_are_unique() {
        use std::collections::HashSet;
        let codes = vec![
            error_codes::PARSE_ERROR,
            error_codes::INVALID_REQUEST,
            error_codes::METHOD_NOT_FOUND,
            error_codes::INVALID_PARAMS,
            error_codes::INTERNAL_ERROR,
            error_codes::NOT_AUTHENTICATED,
            error_codes::NOT_FOUND,
            error_codes::CONFLICT,
        ];
        let set: HashSet<i32> = codes.iter().copied().collect();
        assert_eq!(set.len(), codes.len(), "Duplicate error codes found");
    }

    // =========================================================================
    // Integration / cross-type tests
    // =========================================================================

    #[test]
    fn request_in_response_roundtrip() {
        let req = Request::with_params(Method::SessionGet, serde_json::json!({"id": "sess-1"}));
        let resp = Response::success(&req.id, serde_json::json!({"session": {"id": "sess-1"}}));
        assert_eq!(req.id, resp.id);
    }

    #[test]
    fn all_method_count() {
        // Ensure we have exactly 47 methods by trying to serialize each.
        let methods = vec![
            Method::Health,
            Method::Shutdown,
            Method::AuthStatus,
            Method::AuthLogin,
            Method::AuthCompleteSocial,
            Method::AuthLogout,
            Method::BillingUsageStatus,
            Method::SessionList,
            Method::SessionCreate,
            Method::SessionGet,
            Method::SessionDelete,
            Method::MessageList,
            Method::MessageSend,
            Method::OutboxStatus,
            Method::RepositoryList,
            Method::RepositoryAdd,
            Method::RepositoryRemove,
            Method::RepositoryGetSettings,
            Method::RepositoryUpdateSettings,
            Method::RepositoryListFiles,
            Method::RepositoryReadFile,
            Method::RepositoryReadFileSlice,
            Method::RepositoryWriteFile,
            Method::RepositoryReplaceFileRange,
            Method::ClaudeSend,
            Method::ClaudeStatus,
            Method::ClaudeStop,
            Method::SessionSubscribe,
            Method::SessionUnsubscribe,
            Method::GitStatus,
            Method::GitDiffFile,
            Method::GitLog,
            Method::GitBranches,
            Method::GitStage,
            Method::GitUnstage,
            Method::GitDiscard,
            Method::GitCommitChanges,
            Method::GitPush,
            Method::GhAuthStatus,
            Method::GhPrCreate,
            Method::GhPrView,
            Method::GhPrList,
            Method::GhPrChecks,
            Method::GhPrMerge,
            Method::SystemCheckDependencies,
            Method::TerminalRun,
            Method::TerminalStatus,
            Method::TerminalStop,
        ];
        assert_eq!(methods.len(), 48);
    }
}
