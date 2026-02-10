use crate::itachi::contracts::{
    DecisionResultPayload, UmSecretRequestCommand, UM_SECRET_REQUEST_TYPE,
};
use crate::itachi::errors::DecisionReasonCode;
use crate::itachi::ports::{DecisionKind, Effect, HandlerDeps, LogLevel};
use uuid::Uuid;

/// Validate and route a remote command payload into deterministic effects.
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
    use super::handle_um_secret_request;
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
}
