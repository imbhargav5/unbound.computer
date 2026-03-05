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

                let session_id_clone = session_id.clone();
                let armin_session_id = SessionId::from_string(&session_id);

                // Get messages from Armin (snapshot + delta)
                let snapshot = {
                    let _span = info_span!("armin.snapshot").entered();
                    armin.snapshot()
                };
                let delta = {
                    let _span = info_span!("armin.delta").entered();
                    armin.delta(&armin_session_id)
                };

                // Combine snapshot and delta messages, embedding content as raw JSON
                let messages = {
                    let _span = info_span!("build_json_values").entered();
                    let mut messages = Vec::new();

                    if let Some(session) = snapshot.session(&armin_session_id) {
                        for m in session.messages() {
                            let content_value = serde_json::from_str::<serde_json::Value>(&m.content)
                                .unwrap_or_else(|_| serde_json::Value::String(m.content.clone()));
                            messages.push(serde_json::json!({
                                "id": m.id.as_str(),
                                "session_id": session_id_clone,
                                "content": content_value,
                                "sequence_number": m.sequence_number,
                            }));
                        }
                    }

                    for m in delta.messages() {
                        let content_value = serde_json::from_str::<serde_json::Value>(&m.content)
                            .unwrap_or_else(|_| serde_json::Value::String(m.content.clone()));
                        messages.push(serde_json::json!({
                            "id": m.id.as_str(),
                            "session_id": session_id_clone,
                            "content": content_value,
                            "sequence_number": m.sequence_number,
                        }));
                    }
                    messages
                };

                tracing::debug!(message_count = messages.len(), "message.list complete");

                let response = {
                    let _span = info_span!("build_response").entered();
                    Response::success(
                        &req.id,
                        serde_json::json!({
                            "session_id": session_id_clone,
                            "messages": messages,
                        }),
                    )
                };
                response
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
