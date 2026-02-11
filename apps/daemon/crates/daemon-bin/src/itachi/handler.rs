use crate::itachi::contracts::{
    DecisionResultPayload, RemoteCommandEnvelope, UmSecretRequestCommand,
    UM_SECRET_REQUEST_TYPE,
};
use crate::itachi::errors::DecisionReasonCode;
use crate::itachi::ports::{DecisionKind, Effect, HandlerDeps, LogLevel};
use uuid::Uuid;

/// Supported generic remote command types.
const SUPPORTED_COMMAND_TYPES: &[&str] = &[
    "session.create.v1",
    "claude.send.v1",
    "claude.stop.v1",
];

/// Top-level router: tries generic envelope first, falls back to legacy UM secret format.
pub fn handle_remote_command(payload: &[u8], deps: &HandlerDeps) -> Vec<Effect> {
    // Try parsing as generic RemoteCommandEnvelope (has `params` field)
    if let Ok(envelope) = serde_json::from_slice::<RemoteCommandEnvelope>(payload) {
        // If it's the legacy um.secret.request type, delegate to legacy handler
        if envelope.command_type == UM_SECRET_REQUEST_TYPE {
            return handle_um_secret_request(payload, deps);
        }
        return handle_generic_command(envelope, deps);
    }

    // Fallback: try legacy UmSecretRequestCommand format (no `params` wrapper)
    handle_um_secret_request(payload, deps)
}

/// Route a generic remote command envelope to the appropriate handler.
fn handle_generic_command(envelope: RemoteCommandEnvelope, deps: &HandlerDeps) -> Vec<Effect> {
    // Validate request_id is a UUID
    if Uuid::parse_str(&envelope.request_id).is_err() {
        return reject(
            DecisionReasonCode::InvalidPayload,
            "request_id must be a valid UUID".to_string(),
            Some(envelope.request_id),
            None,
        );
    }

    // Validate requester_device_id is a UUID
    if Uuid::parse_str(&envelope.requester_device_id).is_err() {
        return reject(
            DecisionReasonCode::InvalidPayload,
            "requester_device_id must be a valid UUID".to_string(),
            Some(envelope.request_id),
            None,
        );
    }

    // Validate target_device_id is a UUID
    if Uuid::parse_str(&envelope.target_device_id).is_err() {
        return reject(
            DecisionReasonCode::InvalidPayload,
            "target_device_id must be a valid UUID".to_string(),
            Some(envelope.request_id),
            None,
        );
    }

    // Validate local device identity
    let Some(local_device_id) = deps.local_device_id.as_deref() else {
        return reject(
            DecisionReasonCode::InternalError,
            "local device identity is unavailable".to_string(),
            Some(envelope.request_id),
            None,
        );
    };

    // Validate target matches local device
    if envelope.target_device_id != local_device_id {
        return reject(
            DecisionReasonCode::TargetMismatch,
            format!(
                "target_device_id {} does not match local device",
                envelope.target_device_id
            ),
            Some(envelope.request_id),
            None,
        );
    }

    // Check command type is supported
    if !SUPPORTED_COMMAND_TYPES.contains(&envelope.command_type.as_str()) {
        return reject(
            DecisionReasonCode::UnsupportedCommandType,
            format!("unsupported command type: {}", envelope.command_type),
            Some(envelope.request_id),
            None,
        );
    }

    // Accept and emit execution effect
    let accepted = DecisionResultPayload::accepted(envelope.request_id.clone(), String::new());
    vec![
        Effect::ReturnDecision {
            decision: DecisionKind::AckMessage,
            payload: accepted,
        },
        Effect::RecordMetric {
            name: "remote_command_accepted_total",
        },
        Effect::Log {
            level: LogLevel::Info,
            message: format!(
                "accepted remote command {} (type={})",
                envelope.request_id, envelope.command_type
            ),
        },
        Effect::ExecuteRemoteCommand { envelope },
    ]
}

/// Validate and route a UM secret request payload into deterministic effects.
pub fn handle_um_secret_request(payload: &[u8], deps: &HandlerDeps) -> Vec<Effect> {
    let parsed: UmSecretRequestCommand = match serde_json::from_slice(payload) {
        Ok(v) => v,
        Err(err) => {
            return reject(
                DecisionReasonCode::InvalidPayload,
                format!("invalid JSON payload: {err}"),
                None,
                None,
            );
        }
    };

    if parsed.command_type != UM_SECRET_REQUEST_TYPE {
        return reject(
            DecisionReasonCode::InvalidPayload,
            format!("unsupported command type: {}", parsed.command_type),
            Some(parsed.request_id),
            Some(parsed.session_id),
        );
    }

    if parsed.session_id.trim().is_empty() {
        return reject(
            DecisionReasonCode::InvalidPayload,
            "session_id is required".to_string(),
            Some(parsed.request_id),
            Some(parsed.session_id),
        );
    }

    if Uuid::parse_str(&parsed.request_id).is_err() {
        return reject(
            DecisionReasonCode::InvalidPayload,
            "request_id must be a valid UUID".to_string(),
            Some(parsed.request_id),
            Some(parsed.session_id),
        );
    }

    if Uuid::parse_str(&parsed.requester_device_id).is_err() {
        return reject(
            DecisionReasonCode::InvalidPayload,
            "requester_device_id must be a valid UUID".to_string(),
            Some(parsed.request_id),
            Some(parsed.session_id),
        );
    }

    if Uuid::parse_str(&parsed.target_device_id).is_err() {
        return reject(
            DecisionReasonCode::InvalidPayload,
            "target_device_id must be a valid UUID".to_string(),
            Some(parsed.request_id),
            Some(parsed.session_id),
        );
    }

    let Some(local_device_id) = deps.local_device_id.as_deref() else {
        return reject(
            DecisionReasonCode::InternalError,
            "local device identity is unavailable".to_string(),
            Some(parsed.request_id),
            Some(parsed.session_id),
        );
    };

    if parsed.target_device_id != local_device_id {
        return reject(
            DecisionReasonCode::TargetMismatch,
            format!(
                "target_device_id {} does not match local device",
                parsed.target_device_id
            ),
            Some(parsed.request_id),
            Some(parsed.session_id),
        );
    }

    let accepted =
        DecisionResultPayload::accepted(parsed.request_id.clone(), parsed.session_id.clone());
    vec![
        Effect::ReturnDecision {
            decision: DecisionKind::AckMessage,
            payload: accepted,
        },
        Effect::RecordMetric {
            name: "um_secret_request_received_total",
        },
        Effect::Log {
            level: LogLevel::Info,
            message: format!("accepted um secret request {}", parsed.request_id),
        },
        Effect::ProcessUmSecretRequest { request: parsed },
    ]
}

fn reject(
    reason: DecisionReasonCode,
    message: String,
    request_id: Option<String>,
    session_id: Option<String>,
) -> Vec<Effect> {
    vec![
        Effect::ReturnDecision {
            decision: DecisionKind::DoNotAck,
            payload: DecisionResultPayload::rejected(reason, &message, request_id, session_id),
        },
        Effect::RecordMetric {
            name: "um_secret_ack_rejected_total",
        },
        Effect::Log {
            level: LogLevel::Warn,
            message,
        },
    ]
}

#[cfg(test)]
mod tests {
    use super::{handle_remote_command, handle_um_secret_request};
    use crate::itachi::errors::DecisionReasonCode;
    use crate::itachi::ports::{DecisionKind, Effect, HandlerDeps};
    use serde_json::json;

    fn deps() -> HandlerDeps {
        HandlerDeps {
            local_device_id: Some("00000000-0000-0000-0000-000000000111".to_string()),
            now_ms: 1000,
        }
    }

    #[test]
    fn valid_request_accepts_and_emits_processing_effect() {
        let payload = json!({
            "type": "um.secret.request.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "session_id": "session-1",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "00000000-0000-0000-0000-000000000111",
            "requested_at_ms": 1700000000000_i64
        });

        let effects = handle_um_secret_request(payload.to_string().as_bytes(), &deps());
        assert!(!effects.is_empty());

        match &effects[0] {
            Effect::ReturnDecision { decision, payload } => {
                assert_eq!(*decision, DecisionKind::AckMessage);
                assert_eq!(
                    payload.status,
                    crate::itachi::contracts::DecisionStatus::Accepted
                );
            }
            _ => panic!("first effect must be ReturnDecision"),
        }

        assert!(effects
            .iter()
            .any(|effect| matches!(effect, Effect::ProcessUmSecretRequest { .. })));
    }

    #[test]
    fn invalid_json_rejects() {
        let effects = handle_um_secret_request(b"{not-json", &deps());
        match &effects[0] {
            Effect::ReturnDecision { decision, payload } => {
                assert_eq!(*decision, DecisionKind::DoNotAck);
                assert_eq!(
                    payload.reason_code,
                    Some(DecisionReasonCode::InvalidPayload)
                );
            }
            _ => panic!("first effect must be ReturnDecision"),
        }
    }

    #[test]
    fn wrong_type_rejects() {
        let payload = json!({
            "type": "unknown.command.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "session_id": "session-1",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "00000000-0000-0000-0000-000000000111",
            "requested_at_ms": 1700000000000_i64
        });

        let effects = handle_um_secret_request(payload.to_string().as_bytes(), &deps());
        match &effects[0] {
            Effect::ReturnDecision { payload, .. } => {
                assert_eq!(
                    payload.reason_code,
                    Some(DecisionReasonCode::InvalidPayload)
                );
            }
            _ => panic!("first effect must be ReturnDecision"),
        }
    }

    #[test]
    fn target_mismatch_rejects() {
        let payload = json!({
            "type": "um.secret.request.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "session_id": "session-1",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "00000000-0000-0000-0000-000000000999",
            "requested_at_ms": 1700000000000_i64
        });

        let effects = handle_um_secret_request(payload.to_string().as_bytes(), &deps());
        match &effects[0] {
            Effect::ReturnDecision { payload, .. } => {
                assert_eq!(
                    payload.reason_code,
                    Some(DecisionReasonCode::TargetMismatch)
                );
            }
            _ => panic!("first effect must be ReturnDecision"),
        }
    }

    // --- Generic remote command router tests ---

    #[test]
    fn generic_command_accepts_session_create() {
        let payload = json!({
            "schema_version": 1,
            "type": "session.create.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "00000000-0000-0000-0000-000000000111",
            "requested_at_ms": 1700000000000_i64,
            "params": { "repository_id": "repo-1" }
        });

        let effects = handle_remote_command(payload.to_string().as_bytes(), &deps());
        match &effects[0] {
            Effect::ReturnDecision { decision, .. } => {
                assert_eq!(*decision, DecisionKind::AckMessage);
            }
            _ => panic!("first effect must be ReturnDecision"),
        }
        assert!(effects
            .iter()
            .any(|e| matches!(e, Effect::ExecuteRemoteCommand { .. })));
    }

    #[test]
    fn generic_command_rejects_unsupported_type() {
        let payload = json!({
            "schema_version": 1,
            "type": "unknown.command.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "00000000-0000-0000-0000-000000000111",
            "requested_at_ms": 1700000000000_i64,
            "params": {}
        });

        let effects = handle_remote_command(payload.to_string().as_bytes(), &deps());
        match &effects[0] {
            Effect::ReturnDecision { decision, payload } => {
                assert_eq!(*decision, DecisionKind::DoNotAck);
                assert_eq!(
                    payload.reason_code,
                    Some(DecisionReasonCode::UnsupportedCommandType)
                );
            }
            _ => panic!("first effect must be ReturnDecision"),
        }
    }

    #[test]
    fn generic_command_falls_back_to_legacy_um_secret() {
        // Legacy format: has session_id at top level, no params field
        let payload = json!({
            "type": "um.secret.request.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "session_id": "session-1",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "00000000-0000-0000-0000-000000000111",
            "requested_at_ms": 1700000000000_i64
        });

        let effects = handle_remote_command(payload.to_string().as_bytes(), &deps());
        match &effects[0] {
            Effect::ReturnDecision { decision, .. } => {
                assert_eq!(*decision, DecisionKind::AckMessage);
            }
            _ => panic!("first effect must be ReturnDecision"),
        }
        // Should produce ProcessUmSecretRequest, NOT ExecuteRemoteCommand
        assert!(effects
            .iter()
            .any(|e| matches!(e, Effect::ProcessUmSecretRequest { .. })));
        assert!(!effects
            .iter()
            .any(|e| matches!(e, Effect::ExecuteRemoteCommand { .. })));
    }

    #[test]
    fn generic_command_accepts_claude_send() {
        let payload = json!({
            "schema_version": 1,
            "type": "claude.send.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "00000000-0000-0000-0000-000000000111",
            "requested_at_ms": 1700000000000_i64,
            "params": { "session_id": "abc", "content": "hello" }
        });

        let effects = handle_remote_command(payload.to_string().as_bytes(), &deps());
        match &effects[0] {
            Effect::ReturnDecision { decision, .. } => {
                assert_eq!(*decision, DecisionKind::AckMessage);
            }
            _ => panic!("first effect must be ReturnDecision"),
        }
        assert!(effects
            .iter()
            .any(|e| matches!(e, Effect::ExecuteRemoteCommand { .. })));
    }

    #[test]
    fn generic_command_accepts_claude_stop() {
        let payload = json!({
            "schema_version": 1,
            "type": "claude.stop.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "00000000-0000-0000-0000-000000000111",
            "requested_at_ms": 1700000000000_i64,
            "params": { "session_id": "abc" }
        });

        let effects = handle_remote_command(payload.to_string().as_bytes(), &deps());
        match &effects[0] {
            Effect::ReturnDecision { decision, .. } => {
                assert_eq!(*decision, DecisionKind::AckMessage);
            }
            _ => panic!("first effect must be ReturnDecision"),
        }
        assert!(effects
            .iter()
            .any(|e| matches!(e, Effect::ExecuteRemoteCommand { .. })));
    }

    #[test]
    fn generic_command_invalid_request_id_rejects() {
        let payload = json!({
            "schema_version": 1,
            "type": "session.create.v1",
            "request_id": "not-a-uuid",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "00000000-0000-0000-0000-000000000111",
            "requested_at_ms": 1700000000000_i64,
            "params": {}
        });

        let effects = handle_remote_command(payload.to_string().as_bytes(), &deps());
        match &effects[0] {
            Effect::ReturnDecision { decision, payload } => {
                assert_eq!(*decision, DecisionKind::DoNotAck);
                assert_eq!(
                    payload.reason_code,
                    Some(DecisionReasonCode::InvalidPayload)
                );
                assert!(payload.message.contains("request_id"));
            }
            _ => panic!("first effect must be ReturnDecision"),
        }
    }

    #[test]
    fn generic_command_invalid_requester_device_id_rejects() {
        let payload = json!({
            "schema_version": 1,
            "type": "session.create.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "requester_device_id": "bad-device",
            "target_device_id": "00000000-0000-0000-0000-000000000111",
            "requested_at_ms": 1700000000000_i64,
            "params": {}
        });

        let effects = handle_remote_command(payload.to_string().as_bytes(), &deps());
        match &effects[0] {
            Effect::ReturnDecision { decision, payload } => {
                assert_eq!(*decision, DecisionKind::DoNotAck);
                assert_eq!(
                    payload.reason_code,
                    Some(DecisionReasonCode::InvalidPayload)
                );
                assert!(payload.message.contains("requester_device_id"));
            }
            _ => panic!("first effect must be ReturnDecision"),
        }
    }

    #[test]
    fn generic_command_no_local_device_id_rejects() {
        let deps_no_device = HandlerDeps {
            local_device_id: None,
            now_ms: 1000,
        };

        let payload = json!({
            "schema_version": 1,
            "type": "session.create.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "33333333-3333-3333-3333-333333333333",
            "requested_at_ms": 1700000000000_i64,
            "params": {}
        });

        let effects = handle_remote_command(payload.to_string().as_bytes(), &deps_no_device);
        match &effects[0] {
            Effect::ReturnDecision { decision, payload } => {
                assert_eq!(*decision, DecisionKind::DoNotAck);
                assert_eq!(
                    payload.reason_code,
                    Some(DecisionReasonCode::InternalError)
                );
            }
            _ => panic!("first effect must be ReturnDecision"),
        }
    }

    #[test]
    fn generic_command_envelope_preserved_in_effect() {
        let payload = json!({
            "schema_version": 1,
            "type": "session.create.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "00000000-0000-0000-0000-000000000111",
            "requested_at_ms": 1700000000000_i64,
            "params": { "repository_id": "repo-abc", "title": "My Session" }
        });

        let effects = handle_remote_command(payload.to_string().as_bytes(), &deps());
        let exec_effect = effects
            .iter()
            .find(|e| matches!(e, Effect::ExecuteRemoteCommand { .. }))
            .expect("should have ExecuteRemoteCommand effect");

        if let Effect::ExecuteRemoteCommand { envelope } = exec_effect {
            assert_eq!(envelope.command_type, "session.create.v1");
            assert_eq!(
                envelope.request_id,
                "11111111-1111-1111-1111-111111111111"
            );
            assert_eq!(envelope.params["repository_id"], "repo-abc");
            assert_eq!(envelope.params["title"], "My Session");
        }
    }

    #[test]
    fn generic_command_target_mismatch_rejects() {
        let payload = json!({
            "schema_version": 1,
            "type": "session.create.v1",
            "request_id": "11111111-1111-1111-1111-111111111111",
            "requester_device_id": "22222222-2222-2222-2222-222222222222",
            "target_device_id": "00000000-0000-0000-0000-000000000999",
            "requested_at_ms": 1700000000000_i64,
            "params": {}
        });

        let effects = handle_remote_command(payload.to_string().as_bytes(), &deps());
        match &effects[0] {
            Effect::ReturnDecision { payload, .. } => {
                assert_eq!(
                    payload.reason_code,
                    Some(DecisionReasonCode::TargetMismatch)
                );
            }
            _ => panic!("first effect must be ReturnDecision"),
        }
    }
}
