use serde::{Deserialize, Serialize};

/// Decision-level reject reasons (returned to Nagato for ACK wrapping).
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum DecisionReasonCode {
    InvalidPayload,
    Unauthorized,
    NotFound,
    InternalError,
    TargetMismatch,
    UnsupportedCommandType,
}

/// Response-level error codes published on session-secrets channel.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ResponseErrorCode {
    RequesterKeyNotFound,
    SessionSecretNotFound,
    EncryptionFailed,
    PublishFailed,
    InternalError,
}
