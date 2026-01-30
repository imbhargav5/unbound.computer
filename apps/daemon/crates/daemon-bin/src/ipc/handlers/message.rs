//! Message handlers.

use crate::app::DaemonState;
use daemon_database::{queries, AgentCodingSessionMessage};
use daemon_ipc::{error_codes, IpcServer, Method, Response};
use rayon::prelude::*;
use tracing::debug;

/// Threshold for switching from sequential to parallel decryption.
/// Below this, sequential is faster due to parallelization overhead.
/// Above this, parallel leverages multiple CPU cores for speedup.
const PARALLEL_THRESHOLD: usize = 20;

/// Register message handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    register_message_list(server, state.clone()).await;
    register_message_send(server, state).await;
}

async fn register_message_list(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::MessageList, move |req| {
            let db = state.db.clone();
            let secrets = state.secrets.clone();
            let cached_db_key = *state.db_encryption_key.lock().unwrap();
            let secret_cache = state.session_secret_cache.clone();
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
                let result = tokio::task::spawn_blocking(move || {
                    let conn = db.get()?;
                    let secrets = secrets.lock().unwrap();

                    // Get messages from database
                    let messages = queries::list_messages_for_session(&conn, &session_id)?;

                    // Get session secret (checks cache first, then SQLite, then keychain)
                    let secret_key = secret_cache.get(
                        &conn,
                        &secrets,
                        &session_id,
                        cached_db_key.as_ref(),
                    );

                    // Decrypt all messages (parallel for large batches, sequential for small)
                    let decrypted_contents = decrypt_messages_batch(&messages, secret_key.as_deref());

                    // Build response JSON
                    let message_data: Vec<serde_json::Value> = messages
                        .iter()
                        .zip(decrypted_contents.iter())
                        .map(|(m, content)| {
                            serde_json::json!({
                                "id": m.id,
                                "session_id": m.session_id,
                                "content": content,
                                "sequence_number": m.sequence_number,
                                "timestamp": m.timestamp.to_rfc3339(),
                                "is_streaming": m.is_streaming,
                            })
                        })
                        .collect();

                    Ok::<_, daemon_database::DatabaseError>(message_data)
                })
                .await
                .unwrap();

                match result {
                    Ok(messages) => Response::success(
                        &req.id,
                        serde_json::json!({
                            "session_id": session_id_clone,
                            "messages": messages,
                        }),
                    ),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
                }
            }
        })
        .await;
}

/// Decrypt messages using adaptive parallel/sequential strategy.
///
/// - Below PARALLEL_THRESHOLD: sequential (avoids thread synchronization overhead)
/// - Above PARALLEL_THRESHOLD: parallel using rayon (leverages multiple CPU cores)
///
/// This provides optimal performance across all batch sizes:
/// - Small batches: ~same speed as sequential (no overhead penalty)
/// - Large batches: ~3-4x speedup on multi-core machines
fn decrypt_messages_batch(
    messages: &[AgentCodingSessionMessage],
    key: Option<&[u8]>,
) -> Vec<Option<String>> {
    let Some(key) = key else {
        // No key available - return all None
        return vec![None; messages.len()];
    };

    if messages.len() < PARALLEL_THRESHOLD {
        // Sequential: fewer messages, avoid parallelization overhead
        messages
            .iter()
            .map(|m| decrypt_single_message(m, key))
            .collect()
    } else {
        // Parallel: many messages, leverage multiple CPU cores
        // rayon's par_iter uses work-stealing for automatic load balancing
        messages
            .par_iter()
            .map(|m| decrypt_single_message(m, key))
            .collect()
    }
}

/// Decrypt a single message's content.
#[inline]
fn decrypt_single_message(msg: &AgentCodingSessionMessage, key: &[u8]) -> Option<String> {
    daemon_database::decrypt_content(key, &msg.content_nonce, &msg.content_encrypted)
        .ok()
        .and_then(|bytes| String::from_utf8(bytes).ok())
}

async fn register_message_send(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::MessageSend, move |req| {
            let db = state.db.clone();
            let secrets = state.secrets.clone();
            let cached_db_key = *state.db_encryption_key.lock().unwrap();
            let secret_cache = state.session_secret_cache.clone();
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

                let result = tokio::task::spawn_blocking(move || {
                    let conn = db.get()?;
                    let secrets = secrets.lock().unwrap();

                    // Get or create session secret (checks cache first, then SQLite, then keychain)
                    let key = if let Some(existing_key) = secret_cache.get(
                        &conn,
                        &secrets,
                        &session_id,
                        cached_db_key.as_ref(),
                    ) {
                        existing_key
                    } else {
                        // Generate new session secret
                        let new_secret = daemon_storage::SecretsManager::generate_session_secret();

                        // Use cached database encryption key
                        let db_key = cached_db_key.ok_or_else(|| {
                            daemon_database::DatabaseError::InvalidData(
                                "Device key not found - please set up device trust first"
                                    .to_string(),
                            )
                        })?;

                        // Encrypt the session secret with device key
                        let nonce = daemon_database::generate_nonce();
                        let encrypted_secret = daemon_database::encrypt_content(
                            &db_key,
                            &nonce,
                            new_secret.as_bytes(),
                        )
                        .map_err(|e| daemon_database::DatabaseError::Encryption(e.to_string()))?;

                        // Store in SQLite
                        queries::set_session_secret(
                            &conn,
                            &daemon_database::NewSessionSecret {
                                session_id: session_id.clone(),
                                encrypted_secret,
                                nonce: nonce.to_vec(),
                            },
                        )?;

                        debug!(
                            session_id = %session_id,
                            "Created and stored new session secret in SQLite"
                        );

                        // Parse the new secret to get encryption key
                        daemon_storage::SecretsManager::parse_session_secret(&new_secret)
                            .map_err(|e| daemon_database::DatabaseError::InvalidData(e.to_string()))?
                    };

                    // Encrypt content
                    let nonce = daemon_database::generate_nonce();
                    let content_bytes = content.as_bytes();
                    let encrypted = daemon_database::encrypt_content(&key, &nonce, content_bytes)
                        .map_err(|e| daemon_database::DatabaseError::Encryption(e.to_string()))?;

                    // Get next sequence number
                    let sequence = queries::get_next_message_sequence(&conn, &session_id)?;

                    // Create message with debugging payload
                    let message = daemon_database::NewAgentCodingSessionMessage {
                        id: uuid::Uuid::new_v4().to_string(),
                        session_id: session_id.clone(),
                        content_encrypted: encrypted,
                        content_nonce: nonce.to_vec(),
                        sequence_number: sequence,
                        is_streaming: false,
                        debugging_decrypted_payload: Some(content.clone()),
                    };

                    queries::insert_message(&conn, &message)?;

                    Ok::<_, daemon_database::DatabaseError>(serde_json::json!({
                        "id": message.id,
                        "session_id": message.session_id,
                        "sequence_number": sequence,
                    }))
                })
                .await
                .unwrap();

                match result {
                    Ok(data) => Response::success(&req.id, data),
                    Err(e) => Response::error(&req.id, error_codes::INTERNAL_ERROR, &e.to_string()),
                }
            }
        })
        .await;
}
