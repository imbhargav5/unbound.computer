use crate::itachi::contracts::{
    DecisionResultPayload, RemoteCommandEnvelope, RemoteCommandResponse, UmSecretRequestCommand,
};

/// Daemon decision mapped to Nagato protocol values.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecisionKind {
    AckMessage,
    DoNotAck,
}

/// Log level used by pure handler effects.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogLevel {
    Debug,
    Info,
    Warn,
    Error,
}

/// Inputs used by the pure handler.
#[derive(Debug, Clone)]
pub struct HandlerDeps {
    pub local_device_id: Option<String>,
    pub now_ms: i64,
}

/// Side effects emitted by pure handler.
#[derive(Debug, Clone)]
pub enum Effect {
    ReturnDecision {
        decision: DecisionKind,
        payload: DecisionResultPayload,
    },
    ProcessUmSecretRequest {
        request: UmSecretRequestCommand,
    },
    ExecuteRemoteCommand {
        envelope: RemoteCommandEnvelope,
    },
    PublishRemoteResponse {
        response: RemoteCommandResponse,
    },
    RecordMetric {
        name: &'static str,
    },
    Log {
        level: LogLevel,
        message: String,
    },
}
