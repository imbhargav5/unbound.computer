//! IPC protocol definitions.
//!
//! Uses a JSON-RPC-like protocol over Unix domain sockets.

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
    #[serde(rename = "auth.logout")]
    AuthLogout,

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

// Standard error codes
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

    #[test]
    fn test_request_serialization() {
        let request = Request::new(Method::Health);
        let json = request.to_json().unwrap();

        assert!(json.contains("\"method\":\"health\""));
        assert!(json.contains("\"id\":"));
    }

    #[test]
    fn test_request_with_params() {
        let request = Request::with_params(
            Method::SessionCreate,
            serde_json::json!({ "repository_id": "repo-1" }),
        );
        let json = request.to_json().unwrap();

        assert!(json.contains("\"method\":\"session.create\""));
        assert!(json.contains("\"repository_id\""));
    }

    #[test]
    fn test_response_success() {
        let response = Response::success("123", serde_json::json!({ "status": "ok" }));
        let json = response.to_json().unwrap();

        assert!(json.contains("\"id\":\"123\""));
        assert!(json.contains("\"status\":\"ok\""));
        assert!(!json.contains("\"error\""));
    }

    #[test]
    fn test_response_error() {
        let response = Response::error("123", error_codes::METHOD_NOT_FOUND, "Unknown method");
        let json = response.to_json().unwrap();

        assert!(json.contains("\"id\":\"123\""));
        assert!(json.contains("\"code\":-32601"));
        assert!(json.contains("\"message\":\"Unknown method\""));
        assert!(!json.contains("\"result\""));
    }

    #[test]
    fn test_request_deserialization() {
        let json = r#"{"id":"abc","method":"auth.status"}"#;
        let request: Request = Request::from_json(json).unwrap();

        assert_eq!(request.id, "abc");
        assert_eq!(request.method, Method::AuthStatus);
    }

    #[test]
    fn test_all_methods_serialize() {
        // Test each method variant serializes correctly
        let methods = vec![
            (Method::Health, "health"),
            (Method::Shutdown, "shutdown"),
            (Method::AuthStatus, "auth.status"),
            (Method::AuthLogin, "auth.login"),
            (Method::AuthLogout, "auth.logout"),
            (Method::SessionList, "session.list"),
            (Method::SessionCreate, "session.create"),
            (Method::SessionGet, "session.get"),
            (Method::SessionDelete, "session.delete"),
            (Method::OutboxStatus, "outbox.status"),
            (Method::RepositoryList, "repository.list"),
            (Method::RepositoryAdd, "repository.add"),
            (Method::RepositoryRemove, "repository.remove"),
            (Method::RepositoryListFiles, "repository.list_files"),
            (Method::RepositoryReadFile, "repository.read_file"),
            (
                Method::RepositoryReadFileSlice,
                "repository.read_file_slice",
            ),
            (Method::RepositoryWriteFile, "repository.write_file"),
            (
                Method::RepositoryReplaceFileRange,
                "repository.replace_file_range",
            ),
            (Method::ClaudeSend, "claude.send"),
            (Method::ClaudeStatus, "claude.status"),
            (Method::ClaudeStop, "claude.stop"),
            (Method::GitStatus, "git.status"),
            (Method::GitDiffFile, "git.diff_file"),
            (Method::GitLog, "git.log"),
            (Method::GitBranches, "git.branches"),
            (Method::GitStage, "git.stage"),
            (Method::GitUnstage, "git.unstage"),
            (Method::GitDiscard, "git.discard"),
            (Method::TerminalRun, "terminal.run"),
            (Method::TerminalStatus, "terminal.status"),
            (Method::TerminalStop, "terminal.stop"),
        ];

        for (method, expected_name) in methods {
            let request = Request::new(method.clone());
            let json = request.to_json().unwrap();
            assert!(
                json.contains(&format!("\"method\":\"{}\"", expected_name)),
                "Method {:?} should serialize to {}",
                method,
                expected_name
            );
        }
    }

    #[test]
    fn test_error_info_serialization() {
        let error = ErrorInfo {
            code: error_codes::INTERNAL_ERROR,
            message: "Something went wrong".to_string(),
            data: Some(serde_json::json!({"details": "more info"})),
        };

        let json = serde_json::to_string(&error).unwrap();
        assert!(json.contains("\"code\":-32603"));
        assert!(json.contains("\"message\":\"Something went wrong\""));
        assert!(json.contains("\"details\":\"more info\""));
    }

    #[test]
    fn test_response_is_success() {
        let success = Response::success("1", serde_json::json!({}));
        assert!(success.is_success());

        let error = Response::error("1", error_codes::INTERNAL_ERROR, "Error");
        assert!(!error.is_success());
    }

    #[test]
    fn test_response_error_with_data() {
        let response = Response::error_with_data(
            "123",
            error_codes::INVALID_PARAMS,
            "Invalid parameters",
            serde_json::json!({"field": "name", "reason": "required"}),
        );

        let json = response.to_json().unwrap();
        assert!(json.contains("\"code\":-32602"));
        assert!(json.contains("\"field\":\"name\""));
        assert!(!response.is_success());
    }

    #[test]
    fn test_request_from_json_invalid() {
        // Invalid JSON
        let result = Request::from_json("not json");
        assert!(result.is_err());

        // Missing required fields
        let result = Request::from_json(r#"{"id":"123"}"#);
        assert!(result.is_err());

        // Invalid method
        let result = Request::from_json(r#"{"id":"123","method":"invalid.method"}"#);
        assert!(result.is_err());
    }

    #[test]
    fn test_response_to_json() {
        let response = Response::success("test-id", serde_json::json!({"key": "value"}));
        let json = response.to_json().unwrap();

        // Deserialize back
        let parsed: Response = Response::from_json(&json).unwrap();
        assert_eq!(parsed.id, "test-id");
        assert!(parsed.is_success());
        assert!(parsed.result.is_some());
    }

    #[test]
    fn test_error_codes_values() {
        // Verify error codes are negative and standard JSON-RPC values
        assert_eq!(error_codes::PARSE_ERROR, -32700);
        assert_eq!(error_codes::INVALID_REQUEST, -32600);
        assert_eq!(error_codes::METHOD_NOT_FOUND, -32601);
        assert_eq!(error_codes::INVALID_PARAMS, -32602);
        assert_eq!(error_codes::INTERNAL_ERROR, -32603);
        // Custom error codes
        assert_eq!(error_codes::NOT_AUTHENTICATED, -32001);
        assert_eq!(error_codes::NOT_FOUND, -32002);
        assert_eq!(error_codes::CONFLICT, -32003);
    }

    #[test]
    fn test_request_id_uniqueness() {
        let req1 = Request::new(Method::Health);
        let req2 = Request::new(Method::Health);

        // IDs should be unique (UUIDs)
        assert_ne!(req1.id, req2.id);
        assert!(!req1.id.is_empty());
        assert!(!req2.id.is_empty());
    }
}
