use crate::itachi::errors::{DecisionReasonCode, ResponseErrorCode};
use serde::{Deserialize, Serialize};

pub const UM_SECRET_REQUEST_TYPE: &str = "um.secret.request.v1";
pub const DECISION_SCHEMA_VERSION: u8 = 1;
pub const SESSION_SECRET_RESPONSE_EVENT: &str = "session.secret.response.v1";
pub const SESSION_SECRET_RESPONSE_SCHEMA_VERSION: u8 = 1;
pub const SESSION_SECRET_ALGORITHM: &str = "x25519-hkdf-sha256-chacha20poly1305";
pub const REMOTE_COMMAND_RESPONSE_EVENT: &str = "remote.command.response.v1";

/// Generic remote command envelope sent from iOS via Ably.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RemoteCommandEnvelope {
    pub schema_version: u8,
    #[serde(rename = "type")]
    pub command_type: String,
    pub request_id: String,
    pub requester_device_id: String,
    pub target_device_id: String,
    pub requested_at_ms: i64,
    pub params: serde_json::Value,
}

/// Status of a remote command response.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RemoteCommandStatus {
    Ok,
    Error,
}

/// Response envelope published back to iOS via Falco.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RemoteCommandResponse {
    pub schema_version: u8,
    pub request_id: String,
    #[serde(rename = "type")]
    pub command_type: String,
    pub status: RemoteCommandStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_message: Option<String>,
    pub created_at_ms: i64,
}

impl RemoteCommandResponse {
    pub fn ok(request_id: String, command_type: String, result: serde_json::Value) -> Self {
        Self {
            schema_version: 1,
            request_id,
            command_type,
            status: RemoteCommandStatus::Ok,
            result: Some(result),
            error_code: None,
            error_message: None,
            created_at_ms: chrono::Utc::now().timestamp_millis(),
        }
    }

    pub fn error(
        request_id: String,
        command_type: String,
        error_code: impl Into<String>,
        error_message: impl Into<String>,
    ) -> Self {
        Self {
            schema_version: 1,
            request_id,
            command_type,
            status: RemoteCommandStatus::Error,
            result: None,
            error_code: Some(error_code.into()),
            error_message: Some(error_message.into()),
            created_at_ms: chrono::Utc::now().timestamp_millis(),
        }
    }
}

/// Incoming remote command payload for UM secret sharing.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct UmSecretRequestCommand {
    #[serde(rename = "type")]
    pub command_type: String,
    pub request_id: String,
    pub session_id: String,
    pub requester_device_id: String,
    pub target_device_id: String,
    pub requested_at_ms: i64,
}

/// Decision status encoded in daemon decision result payload.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DecisionStatus {
    Accepted,
    Rejected,
}

/// JSON result body sent back to Nagato in daemon decision frame.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DecisionResultPayload {
    pub schema_version: u8,
    pub request_id: Option<String>,
    pub session_id: Option<String>,
    pub status: DecisionStatus,
    pub reason_code: Option<DecisionReasonCode>,
    pub message: String,
}

impl DecisionResultPayload {
    pub fn accepted(request_id: String, session_id: String) -> Self {
        Self {
            schema_version: DECISION_SCHEMA_VERSION,
            request_id: Some(request_id),
            session_id: Some(session_id),
            status: DecisionStatus::Accepted,
            reason_code: None,
            message: "accepted".to_string(),
        }
    }

    pub fn rejected(
        reason_code: DecisionReasonCode,
        message: impl Into<String>,
        request_id: Option<String>,
        session_id: Option<String>,
    ) -> Self {
        Self {
            schema_version: DECISION_SCHEMA_VERSION,
            request_id,
            session_id,
            status: DecisionStatus::Rejected,
            reason_code: Some(reason_code),
            message: message.into(),
        }
    }
}

/// Response status for session secret channel.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SessionSecretResponseStatus {
    Ok,
    Error,
}

/// Payload published on `session.secret.response.v1`.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SessionSecretResponsePayload {
    pub schema_version: u8,
    pub request_id: String,
    pub session_id: String,
    pub sender_device_id: String,
    pub receiver_device_id: String,
    pub status: SessionSecretResponseStatus,
    pub error_code: Option<ResponseErrorCode>,
    pub ciphertext_b64: Option<String>,
    pub encapsulation_pubkey_b64: Option<String>,
    pub nonce_b64: Option<String>,
    pub algorithm: String,
    pub created_at_ms: i64,
}

impl SessionSecretResponsePayload {
    pub fn ok(
        request_id: String,
        session_id: String,
        sender_device_id: String,
        receiver_device_id: String,
        ciphertext_b64: String,
        encapsulation_pubkey_b64: String,
        nonce_b64: String,
        created_at_ms: i64,
    ) -> Self {
        Self {
            schema_version: SESSION_SECRET_RESPONSE_SCHEMA_VERSION,
            request_id,
            session_id,
            sender_device_id,
            receiver_device_id,
            status: SessionSecretResponseStatus::Ok,
            error_code: None,
            ciphertext_b64: Some(ciphertext_b64),
            encapsulation_pubkey_b64: Some(encapsulation_pubkey_b64),
            nonce_b64: Some(nonce_b64),
            algorithm: SESSION_SECRET_ALGORITHM.to_string(),
            created_at_ms,
        }
    }

    pub fn error(
        request_id: String,
        session_id: String,
        sender_device_id: String,
        receiver_device_id: String,
        error_code: ResponseErrorCode,
        created_at_ms: i64,
    ) -> Self {
        Self {
            schema_version: SESSION_SECRET_RESPONSE_SCHEMA_VERSION,
            request_id,
            session_id,
            sender_device_id,
            receiver_device_id,
            status: SessionSecretResponseStatus::Error,
            error_code: Some(error_code),
            ciphertext_b64: None,
            encapsulation_pubkey_b64: None,
            nonce_b64: None,
            algorithm: SESSION_SECRET_ALGORITHM.to_string(),
            created_at_ms,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn remote_command_envelope_round_trip() {
        let envelope = RemoteCommandEnvelope {
            schema_version: 1,
            command_type: "session.create.v1".to_string(),
            request_id: "11111111-1111-1111-1111-111111111111".to_string(),
            requester_device_id: "22222222-2222-2222-2222-222222222222".to_string(),
            target_device_id: "33333333-3333-3333-3333-333333333333".to_string(),
            requested_at_ms: 1700000000000,
            params: json!({"repository_id": "repo-1"}),
        };

        let serialized = serde_json::to_string(&envelope).unwrap();
        let deserialized: RemoteCommandEnvelope = serde_json::from_str(&serialized).unwrap();
        assert_eq!(deserialized, envelope);
    }

    #[test]
    fn remote_command_envelope_type_field_renamed() {
        let envelope = RemoteCommandEnvelope {
            schema_version: 1,
            command_type: "claude.send.v1".to_string(),
            request_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa".to_string(),
            requester_device_id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb".to_string(),
            target_device_id: "cccccccc-cccc-cccc-cccc-cccccccccccc".to_string(),
            requested_at_ms: 1700000000000,
            params: json!({}),
        };

        let value: serde_json::Value = serde_json::to_value(&envelope).unwrap();
        // "type" field should be used in JSON, not "command_type"
        assert_eq!(value["type"], "claude.send.v1");
        assert!(value.get("command_type").is_none());
    }

    #[test]
    fn remote_command_envelope_deserializes_from_json() {
        let json_str = r#"{
            "schema_version": 1,
            "type": "claude.stop.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "33333333-3333-3333-3333-333333333333",
            "requested_at_ms": 1700000000000,
            "params": {"session_id": "abc-123"}
        }"#;

        let envelope: RemoteCommandEnvelope = serde_json::from_str(json_str).unwrap();
        assert_eq!(envelope.command_type, "claude.stop.v1");
        assert_eq!(envelope.params["session_id"], "abc-123");
    }

    #[test]
    fn remote_command_status_serializes_snake_case() {
        assert_eq!(
            serde_json::to_value(RemoteCommandStatus::Ok).unwrap(),
            json!("ok")
        );
        assert_eq!(
            serde_json::to_value(RemoteCommandStatus::Error).unwrap(),
            json!("error")
        );
    }

    #[test]
    fn remote_command_response_ok_factory() {
        let resp = RemoteCommandResponse::ok(
            "req-1".to_string(),
            "session.create.v1".to_string(),
            json!({"id": "session-abc"}),
        );

        assert_eq!(resp.status, RemoteCommandStatus::Ok);
        assert_eq!(resp.request_id, "req-1");
        assert_eq!(resp.command_type, "session.create.v1");
        assert_eq!(resp.result, Some(json!({"id": "session-abc"})));
        assert!(resp.error_code.is_none());
        assert!(resp.error_message.is_none());
    }

    #[test]
    fn remote_command_response_error_factory() {
        let resp = RemoteCommandResponse::error(
            "req-2".to_string(),
            "claude.send.v1".to_string(),
            "invalid_params",
            "session_id is required",
        );

        assert_eq!(resp.status, RemoteCommandStatus::Error);
        assert_eq!(resp.error_code, Some("invalid_params".to_string()));
        assert_eq!(
            resp.error_message,
            Some("session_id is required".to_string())
        );
        assert!(resp.result.is_none());
    }

    #[test]
    fn remote_command_response_omits_none_fields() {
        let resp = RemoteCommandResponse::ok(
            "req-3".to_string(),
            "claude.stop.v1".to_string(),
            json!({"stopped": true}),
        );

        let value = serde_json::to_value(&resp).unwrap();
        assert!(value.get("error_code").is_none());
        assert!(value.get("error_message").is_none());
        assert!(value.get("result").is_some());
    }

    #[test]
    fn remote_command_response_round_trip() {
        let resp = RemoteCommandResponse::error(
            "req-4".to_string(),
            "session.create.v1".to_string(),
            "not_found",
            "repository not found",
        );

        let serialized = serde_json::to_string(&resp).unwrap();
        let deserialized: RemoteCommandResponse = serde_json::from_str(&serialized).unwrap();
        assert_eq!(deserialized.request_id, resp.request_id);
        assert_eq!(deserialized.status, RemoteCommandStatus::Error);
        assert_eq!(deserialized.error_code, Some("not_found".to_string()));
    }
}
