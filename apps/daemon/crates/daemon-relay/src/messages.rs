//! Relay protocol messages.

use serde::{Deserialize, Serialize};

/// Relay message types.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum RelayMessageType {
    // Connection
    Auth,
    AuthResult,
    Error,

    // Sessions
    JoinSession,
    LeaveSession,
    Subscribed,
    Unsubscribed,

    // Streaming
    #[serde(rename = "stream_chunk")]
    StreamChunk,
    #[serde(rename = "stream_complete")]
    StreamComplete,

    // Remote control
    #[serde(rename = "remote_control")]
    RemoteControl,
    #[serde(rename = "control_ack")]
    ControlAck,

    // Presence
    #[serde(rename = "presence")]
    Presence,
    Heartbeat,

    // Messages
    #[serde(rename = "SESSION_MESSAGE")]
    SessionMessage,
    #[serde(rename = "SESSION_MESSAGE_ACK")]
    SessionMessageAck,
}

/// A message sent to/from the relay.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RelayMessage {
    #[serde(rename = "type")]
    pub msg_type: RelayMessageType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub payload: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub timestamp: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub success: Option<bool>,
}

impl RelayMessage {
    /// Create a new relay message.
    pub fn new(msg_type: RelayMessageType) -> Self {
        Self {
            msg_type,
            session_id: None,
            payload: None,
            timestamp: Some(chrono::Utc::now().to_rfc3339()),
            error: None,
            success: None,
        }
    }

    /// Create an AUTH message.
    pub fn auth(device_token: &str, device_id: &str) -> Self {
        Self {
            msg_type: RelayMessageType::Auth,
            session_id: None,
            payload: Some(serde_json::json!({
                "deviceToken": device_token,
                "deviceId": device_id
            })),
            timestamp: Some(chrono::Utc::now().to_rfc3339()),
            error: None,
            success: None,
        }
    }

    /// Create a JOIN_SESSION message.
    pub fn join_session(session_id: &str) -> Self {
        Self {
            msg_type: RelayMessageType::JoinSession,
            session_id: Some(session_id.to_string()),
            payload: None,
            timestamp: Some(chrono::Utc::now().to_rfc3339()),
            error: None,
            success: None,
        }
    }

    /// Create a LEAVE_SESSION message.
    pub fn leave_session(session_id: &str) -> Self {
        Self {
            msg_type: RelayMessageType::LeaveSession,
            session_id: Some(session_id.to_string()),
            payload: None,
            timestamp: Some(chrono::Utc::now().to_rfc3339()),
            error: None,
            success: None,
        }
    }

    /// Create a HEARTBEAT message.
    pub fn heartbeat() -> Self {
        Self::new(RelayMessageType::Heartbeat)
    }

    /// Create a SESSION_MESSAGE message.
    pub fn session_message(session_id: &str, payload: serde_json::Value) -> Self {
        Self {
            msg_type: RelayMessageType::SessionMessage,
            session_id: Some(session_id.to_string()),
            payload: Some(payload),
            timestamp: Some(chrono::Utc::now().to_rfc3339()),
            error: None,
            success: None,
        }
    }

    /// Set the session ID.
    pub fn with_session(mut self, session_id: &str) -> Self {
        self.session_id = Some(session_id.to_string());
        self
    }

    /// Set the payload.
    pub fn with_payload(mut self, payload: serde_json::Value) -> Self {
        self.payload = Some(payload);
        self
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

/// Auth result payload.
#[derive(Debug, Clone, Deserialize)]
pub struct AuthResultPayload {
    pub success: bool,
    #[serde(default)]
    pub error: Option<String>,
}

/// Session subscription result.
#[derive(Debug, Clone, Deserialize)]
pub struct SubscriptionResult {
    #[serde(rename = "sessionId")]
    pub session_id: String,
    pub success: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_auth_message() {
        let msg = RelayMessage::auth("token123", "device456");
        let json = msg.to_json().unwrap();

        assert!(json.contains("\"type\":\"AUTH\""));
        assert!(json.contains("\"deviceToken\":\"token123\""));
        assert!(json.contains("\"deviceId\":\"device456\""));
    }

    #[test]
    fn test_join_session_message() {
        let msg = RelayMessage::join_session("session789");
        let json = msg.to_json().unwrap();

        assert!(json.contains("\"type\":\"JOIN_SESSION\""));
        assert!(json.contains("\"sessionId\":\"session789\""));
    }

    #[test]
    fn test_heartbeat_message() {
        let msg = RelayMessage::heartbeat();
        let json = msg.to_json().unwrap();

        assert!(json.contains("\"type\":\"HEARTBEAT\""));
    }

    #[test]
    fn test_deserialize_auth_result() {
        let json = r#"{"type":"AUTH_RESULT","success":true}"#;
        let msg: RelayMessage = serde_json::from_str(json).unwrap();

        assert_eq!(msg.msg_type, RelayMessageType::AuthResult);
        assert_eq!(msg.success, Some(true));
    }

    #[test]
    fn test_leave_session_message() {
        let msg = RelayMessage::leave_session("session-to-leave");
        let json = msg.to_json().unwrap();

        assert!(json.contains("\"type\":\"LEAVE_SESSION\""));
        assert!(json.contains("\"sessionId\":\"session-to-leave\""));
        assert!(msg.timestamp.is_some());
    }

    #[test]
    fn test_session_message() {
        let payload = serde_json::json!({"event": "test", "data": {"key": "value"}});
        let msg = RelayMessage::session_message("session-123", payload);
        let json = msg.to_json().unwrap();

        assert!(json.contains("\"type\":\"SESSION_MESSAGE\""));
        assert!(json.contains("\"sessionId\":\"session-123\""));
        assert!(json.contains("\"event\":\"test\""));
    }

    #[test]
    fn test_relay_event_message() {
        // Test creating a new message
        let msg = RelayMessage::new(RelayMessageType::StreamChunk);
        let json = msg.to_json().unwrap();

        assert!(json.contains("\"type\":\"stream_chunk\""));
        assert!(msg.timestamp.is_some());
    }

    #[test]
    fn test_message_type_variants() {
        // Test all message type variants serialize correctly
        let types = vec![
            (RelayMessageType::Auth, "AUTH"),
            (RelayMessageType::AuthResult, "AUTH_RESULT"),
            (RelayMessageType::Error, "ERROR"),
            (RelayMessageType::JoinSession, "JOIN_SESSION"),
            (RelayMessageType::LeaveSession, "LEAVE_SESSION"),
            (RelayMessageType::Subscribed, "SUBSCRIBED"),
            (RelayMessageType::Unsubscribed, "UNSUBSCRIBED"),
            (RelayMessageType::StreamChunk, "stream_chunk"),
            (RelayMessageType::StreamComplete, "stream_complete"),
            (RelayMessageType::RemoteControl, "remote_control"),
            (RelayMessageType::ControlAck, "control_ack"),
            (RelayMessageType::Presence, "presence"),
            (RelayMessageType::Heartbeat, "HEARTBEAT"),
            (RelayMessageType::SessionMessage, "SESSION_MESSAGE"),
            (RelayMessageType::SessionMessageAck, "SESSION_MESSAGE_ACK"),
        ];

        for (msg_type, expected_name) in types {
            let msg = RelayMessage::new(msg_type);
            let json = msg.to_json().unwrap();
            assert!(json.contains(&format!("\"type\":\"{}\"", expected_name)),
                "Expected type {} in JSON", expected_name);
        }
    }

    #[test]
    fn test_message_with_session() {
        let msg = RelayMessage::new(RelayMessageType::StreamChunk)
            .with_session("my-session");

        assert_eq!(msg.session_id, Some("my-session".to_string()));
    }

    #[test]
    fn test_message_with_payload() {
        let payload = serde_json::json!({"key": "value"});
        let msg = RelayMessage::new(RelayMessageType::StreamChunk)
            .with_payload(payload);

        assert!(msg.payload.is_some());
        let p = msg.payload.unwrap();
        assert_eq!(p["key"], "value");
    }

    #[test]
    fn test_message_roundtrip() {
        let original = RelayMessage::auth("my-token", "my-device");
        let json = original.to_json().unwrap();
        let parsed = RelayMessage::from_json(&json).unwrap();

        assert_eq!(parsed.msg_type, RelayMessageType::Auth);
        assert!(parsed.payload.is_some());
    }

    #[test]
    fn test_message_error_field() {
        let json = r#"{"type":"ERROR","error":"Something went wrong"}"#;
        let msg: RelayMessage = serde_json::from_str(json).unwrap();

        assert_eq!(msg.msg_type, RelayMessageType::Error);
        assert_eq!(msg.error, Some("Something went wrong".to_string()));
    }

    #[test]
    fn test_subscription_result_deserialize() {
        let json = r#"{"sessionId":"session-abc","success":true}"#;
        let result: SubscriptionResult = serde_json::from_str(json).unwrap();

        assert_eq!(result.session_id, "session-abc");
        assert!(result.success);
    }

    #[test]
    fn test_auth_result_payload_deserialize() {
        let json = r#"{"success":false,"error":"Invalid token"}"#;
        let result: AuthResultPayload = serde_json::from_str(json).unwrap();

        assert!(!result.success);
        assert_eq!(result.error, Some("Invalid token".to_string()));
    }
}
