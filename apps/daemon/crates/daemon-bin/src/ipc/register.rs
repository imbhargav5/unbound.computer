//! Handler registration for the IPC server.

use crate::app::DaemonState;
use crate::auth;
use crate::ipc::handlers;
use daemon_database::queries;
use daemon_ipc::{Event, EventType, IpcServer};
use tracing::{info, warn};

/// Register all IPC handlers.
pub async fn register_handlers(server: &IpcServer, state: DaemonState) {
    // Register all handler modules
    handlers::health::register(server).await;
    auth::register_handlers(server, state.clone()).await;
    handlers::session::register(server, state.clone()).await;
    handlers::repository::register(server, state.clone()).await;
    handlers::message::register(server, state.clone()).await;
    handlers::claude::register(server, state.clone()).await;
    handlers::terminal::register(server, state.clone()).await;
    handlers::git::register(server, state.clone()).await;

    // Register initial state handler for subscriptions
    register_initial_state_handler(server, state).await;

    info!("All IPC handlers registered");
}

/// Register the initial state handler for subscriptions.
async fn register_initial_state_handler(server: &IpcServer, state: DaemonState) {
    server
        .register_initial_state_handler(move |session_id| {
            let state = state.clone();
            async move {
                // Get session secret (checks cache first, then SQLite, then keychain)
                let conn = match state.db.get() {
                    Ok(c) => c,
                    Err(_) => return None,
                };
                let secrets = state.secrets.lock().unwrap();
                let cached_db_key = *state.db_encryption_key.lock().unwrap();

                let key = match state.session_secret_cache.get(
                    &conn,
                    &secrets,
                    &session_id,
                    cached_db_key.as_ref(),
                ) {
                    Some(k) => k,
                    None => {
                        warn!(
                            session_id = %session_id,
                            "No session secret found - cannot load messages"
                        );
                        return None;
                    }
                };

                // Get messages for this session
                let messages = {
                    let conn = match state.db.get() {
                        Ok(c) => c,
                        Err(_) => return None,
                    };
                    match queries::list_messages_for_session(&conn, &session_id) {
                        Ok(msgs) => msgs,
                        Err(_) => return None,
                    }
                };

                // Convert to events
                let mut events = Vec::new();
                let mut max_seq = 0i64;
                for msg in messages {
                    // Decrypt content
                    let content = match daemon_database::decrypt_content(
                        &key,
                        &msg.content_nonce,
                        &msg.content_encrypted,
                    ) {
                        Ok(bytes) => String::from_utf8_lossy(&bytes).to_string(),
                        Err(_) => continue,
                    };

                    events.push(Event::new(
                        EventType::InitialState,
                        &session_id,
                        serde_json::json!({
                            "content": content,
                        }),
                        msg.sequence_number,
                    ));

                    if msg.sequence_number > max_seq {
                        max_seq = msg.sequence_number;
                    }
                }

                Some((events, max_seq))
            }
        })
        .await;
}
