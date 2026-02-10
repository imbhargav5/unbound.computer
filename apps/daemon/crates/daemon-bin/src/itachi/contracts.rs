use crate::itachi::errors::{DecisionReasonCode, ResponseErrorCode};
use serde::{Deserialize, Serialize};

pub const UM_SECRET_REQUEST_TYPE: &str = "um.secret.request.v1";
pub const DECISION_SCHEMA_VERSION: u8 = 1;
pub const SESSION_SECRET_RESPONSE_EVENT: &str = "session.secret.response.v1";
pub const SESSION_SECRET_RESPONSE_SCHEMA_VERSION: u8 = 1;
pub const SESSION_SECRET_ALGORITHM: &str = "x25519-hkdf-sha256-chacha20poly1305";

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
