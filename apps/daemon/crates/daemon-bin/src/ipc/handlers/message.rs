//! Message handlers.

use crate::app::DaemonState;
use agent_session_sqlite_persist_core::{NewMessage, SessionId, SessionReader, SessionWriter};
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use tracing::info_span;

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

                // Get snapshot messages (borrowed from the snapshot view)
                let snapshot = {
                    let _span = info_span!("armin.snapshot").entered();
                    armin.snapshot()
                };
                let snapshot_msgs: &[agent_session_sqlite_persist_core::Message] =
                    snapshot.session(&armin_session_id)
                        .map(|s| s.messages())
                        .unwrap_or(&[]);

                // Build JSON directly into a pre-sized buffer.
                // Delta messages are accessed by reference via closure (zero-copy).
                let raw_json = armin.with_delta_messages(&armin_session_id, |delta_msgs| {
                    let _span = info_span!("build_json").entered();
                    let session_id_json = serde_json::to_string(&session_id).unwrap();
                    let total = snapshot_msgs.len() + delta_msgs.len();
                    let content_size: usize = snapshot_msgs.iter().chain(delta_msgs.iter())
                        .map(|m| m.content.len()).sum();

                    tracing::debug!(message_count = total, "message.list complete");

                    // Pre-allocate: content + ~120 bytes overhead per message + envelope
                    let mut buf = String::with_capacity(content_size + total * 120 + 100);
                    buf.push_str(r#"{"session_id":"#);
                    buf.push_str(&session_id_json);
                    buf.push_str(r#","messages":["#);

                    let mut first = true;
                    for m in snapshot_msgs.iter().chain(delta_msgs.iter()) {
                        if !first { buf.push(','); }
                        first = false;
                        buf.push_str(r#"{"id":""#);
                        buf.push_str(m.id.as_str());
                        buf.push_str(r#"","session_id":"#);
                        buf.push_str(&session_id_json);
                        buf.push_str(r#","content":"#);
                        // Content from Claude events is valid JSON — embed verbatim.
                        // Content from message.send is plain text — JSON-string-encode it.
                        if serde_json::from_str::<&serde_json::value::RawValue>(&m.content).is_ok() {
                            buf.push_str(&m.content);
                        } else {
                            buf.push_str(&serde_json::to_string(&m.content).unwrap());
                        }
                        buf.push_str(r#","sequence_number":"#);
                        buf.push_str(&m.sequence_number.to_string());
                        buf.push('}');
                    }
                    buf.push_str("]}");
                    buf
                });

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
