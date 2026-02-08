//! Shared auth side effects for daemon state updates.

use crate::app::DaemonState;
use toshinori::SyncContext;
use ymir::AuthLoginResult;

/// Apply in-memory cache updates and sync contexts after successful login.
pub async fn apply_login_side_effects(state: &DaemonState, login: &AuthLoginResult) {
    *state.device_id.lock().unwrap() = Some(login.device_id.clone());
    *state.device_private_key.lock().unwrap() = Some(login.device_private_key);
    *state.db_encryption_key.lock().unwrap() = login.db_encryption_key;

    let sync_context = SyncContext {
        access_token: login.access_token.clone(),
        user_id: login.user_id.clone(),
        device_id: login.device_id.clone(),
    };
    state.toshinori.set_context(sync_context.clone()).await;
    state.message_sync.set_context(sync_context).await;
}

/// Clear sync contexts after logout.
pub async fn clear_login_side_effects(state: &DaemonState) {
    state.toshinori.clear_context().await;
    state.message_sync.clear_context().await;
}
