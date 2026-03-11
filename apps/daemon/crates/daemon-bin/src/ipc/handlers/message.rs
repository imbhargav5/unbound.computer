//! Message handlers.

use crate::app::DaemonState;
use agent_session_sqlite_persist_core::{
    Message, NewMessage, SessionId, SessionReader, SessionWriter,
};
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use tracing::info_span;

#[derive(Debug, Clone, Copy)]
struct MessageListPlan {
    snapshot_count: usize,
    delta_count: usize,
    total_count: usize,
    content_bytes: usize,
    estimated_response_bytes: usize,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
struct MessageListEncodeStats {
    json_content_count: usize,
    string_content_count: usize,
}

fn plan_message_list(snapshot_msgs: &[Message], delta_msgs: &[Message]) -> MessageListPlan {
    let total_count = snapshot_msgs.len() + delta_msgs.len();
    let content_bytes = snapshot_msgs
        .iter()
        .chain(delta_msgs.iter())
        .map(|m| m.content.len())
        .sum();

    MessageListPlan {
        snapshot_count: snapshot_msgs.len(),
        delta_count: delta_msgs.len(),
        total_count,
        content_bytes,
        estimated_response_bytes: content_bytes + total_count * 120 + 100,
    }
}

fn build_message_list_json(
    session_id_json: &str,
    snapshot_msgs: &[Message],
    delta_msgs: &[Message],
    plan: MessageListPlan,
) -> (String, MessageListEncodeStats) {
    let mut stats = MessageListEncodeStats::default();

    // Pre-allocate: content + ~120 bytes overhead per message + envelope
    let mut buf = String::with_capacity(plan.estimated_response_bytes);
    buf.push_str(r#"{"session_id":"#);
    buf.push_str(session_id_json);
    buf.push_str(r#","messages":["#);

    let mut first = true;
    for m in snapshot_msgs.iter().chain(delta_msgs.iter()) {
        if !first {
            buf.push(',');
        }
        first = false;
        buf.push_str(r#"{"id":""#);
        buf.push_str(m.id.as_str());
        buf.push_str(r#"","session_id":"#);
        buf.push_str(session_id_json);
        buf.push_str(r#","content":"#);
        // Content from Claude events is valid JSON - embed verbatim.
        // Content from message.send is plain text - JSON-string-encode it.
        if serde_json::from_str::<&serde_json::value::RawValue>(&m.content).is_ok() {
            stats.json_content_count += 1;
            buf.push_str(&m.content);
        } else {
            stats.string_content_count += 1;
            buf.push_str(&serde_json::to_string(&m.content).unwrap());
        }
        buf.push_str(r#","sequence_number":"#);
        buf.push_str(&m.sequence_number.to_string());
        buf.push('}');
    }
    buf.push_str("]}");

    (buf, stats)
}

/// Register message handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_message_list(server, state.clone()).await;
    register_message_send(server, state).await;
}

async fn register_message_list(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::MessageList, move |req| {
            let armin = state.armin.clone();
            async move {
                let session_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("session_id"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let Some(session_id) = session_id else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "session_id is required",
                    );
                };

                let armin_session_id = SessionId::from_string(&session_id);

                let snapshot_read_span =
                    info_span!("message.list.snapshot.read", session_id = %session_id);
                let snapshot = {
                    let _span = snapshot_read_span.enter();
                    armin.snapshot()
                };
                let snapshot_lookup_span = info_span!(
                    "message.list.snapshot.lookup",
                    session_id = %session_id,
                    snapshot_count = tracing::field::Empty
                );
                let snapshot_msgs: &[Message] = {
                    let _span = snapshot_lookup_span.enter();
                    let snapshot_msgs = snapshot
                        .session(&armin_session_id)
                        .map(|s| s.messages())
                        .unwrap_or(&[]);
                    snapshot_lookup_span.record("snapshot_count", snapshot_msgs.len());
                    snapshot_msgs
                };

                let delta_read_span = info_span!(
                    "message.list.delta.read",
                    session_id = %session_id,
                    delta_count = tracing::field::Empty
                );
                let raw_json = {
                    let _delta_span = delta_read_span.enter();
                    // Build JSON directly into a pre-sized buffer.
                    // Delta messages are accessed by reference via closure (zero-copy).
                    armin.with_delta_messages(&armin_session_id, |delta_msgs| {
                        delta_read_span.record("delta_count", delta_msgs.len());
                        let json_plan_span = info_span!(
                            "message.list.json.plan",
                            session_id = %session_id,
                            snapshot_count = tracing::field::Empty,
                            delta_count = tracing::field::Empty,
                            total_count = tracing::field::Empty,
                            content_bytes = tracing::field::Empty,
                            estimated_response_bytes = tracing::field::Empty
                        );
                        let plan = {
                            let _plan_span = json_plan_span.enter();
                            let plan = plan_message_list(snapshot_msgs, delta_msgs);
                            json_plan_span.record("snapshot_count", plan.snapshot_count);
                            json_plan_span.record("delta_count", plan.delta_count);
                            json_plan_span.record("total_count", plan.total_count);
                            json_plan_span.record("content_bytes", plan.content_bytes);
                            json_plan_span
                                .record("estimated_response_bytes", plan.estimated_response_bytes);
                            plan
                        };

                        let json_encode_span = info_span!(
                            "message.list.json.encode",
                            session_id = %session_id,
                            snapshot_count = plan.snapshot_count,
                            delta_count = plan.delta_count,
                            total_count = plan.total_count,
                            content_bytes = plan.content_bytes,
                            estimated_response_bytes = plan.estimated_response_bytes,
                            json_content_count = tracing::field::Empty,
                            string_content_count = tracing::field::Empty
                        );
                        let session_id_json = serde_json::to_string(&session_id).unwrap();
                        let (raw_json, encode_stats) = {
                            let _encode_span = json_encode_span.enter();
                            build_message_list_json(
                                &session_id_json,
                                snapshot_msgs,
                                delta_msgs,
                                plan,
                            )
                        };
                        json_encode_span
                            .record("json_content_count", encode_stats.json_content_count);
                        json_encode_span
                            .record("string_content_count", encode_stats.string_content_count);

                        tracing::debug!(
                            message_count = plan.total_count,
                            json_content_count = encode_stats.json_content_count,
                            string_content_count = encode_stats.string_content_count,
                            "message.list complete"
                        );

                        raw_json
                    })
                };

                Response::success_raw(&req.id, raw_json)
            }
        })
        .await;
}

async fn register_message_send(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::MessageSend, move |req| {
            let armin = state.armin.clone();
            async move {
                let session_id = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("session_id"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let content = req
                    .params
                    .as_ref()
                    .and_then(|p| p.get("content"))
                    .and_then(|v| v.as_str())
                    .map(String::from);

                let (Some(session_id), Some(content)) = (session_id, content) else {
                    return Response::error(
                        &req.id,
                        error_codes::INVALID_PARAMS,
                        "session_id and content are required",
                    );
                };

                let armin_session_id = SessionId::from_string(&session_id);

                // Append message via Armin (sequence number assigned atomically)
                let message = match armin.append(
                    &armin_session_id,
                    NewMessage {
                        content: content.clone(),
                    },
                ) {
                    Ok(msg) => msg,
                    Err(e) => {
                        return Response::error(
                            &req.id,
                            error_codes::INTERNAL_ERROR,
                            &format!("Failed to append message: {}", e),
                        );
                    }
                };

                Response::success(
                    &req.id,
                    serde_json::json!({
                        "id": message.id.as_str(),
                        "session_id": session_id,
                        "sequence_number": message.sequence_number,
                    }),
                )
            }
        })
        .await;
}

#[cfg(test)]
mod tests {
    use super::*;
    use agent_session_sqlite_persist_core::MessageId;

    #[test]
    fn build_message_list_json_preserves_mixed_message_content() {
        let session_id_json = serde_json::to_string("session-1").unwrap();
        let snapshot_msgs = vec![Message {
            id: MessageId::from_string("msg-1"),
            content: r#"{"kind":"assistant"}"#.to_string(),
            sequence_number: 1,
        }];
        let delta_msgs = vec![Message {
            id: MessageId::from_string("msg-2"),
            content: "plain text".to_string(),
            sequence_number: 2,
        }];
        let plan = plan_message_list(&snapshot_msgs, &delta_msgs);

        let (raw_json, stats) =
            build_message_list_json(&session_id_json, &snapshot_msgs, &delta_msgs, plan);
        let parsed: serde_json::Value = serde_json::from_str(&raw_json).unwrap();

        assert_eq!(parsed["session_id"], "session-1");
        assert_eq!(parsed["messages"][0]["content"]["kind"], "assistant");
        assert_eq!(parsed["messages"][1]["content"], "plain text");
        assert_eq!(stats.json_content_count, 1);
        assert_eq!(stats.string_content_count, 1);
    }
}
