//! Shared auth side effects for daemon state updates.

use crate::app::falco_sidecar::{ensure_socket_connectable, start_falco_sidecar, terminate_child};
use crate::app::nagato_sidecar::start_nagato_sidecar;
use crate::app::DaemonState;
use std::sync::Arc;
use std::time::Duration;
use toshinori::{AblyRealtimeSyncer, AblySyncConfig, SyncContext};
use tracing::{info, warn};
use ymir::AuthLoginResult;

/// Apply in-memory cache updates and sync contexts after successful login.
pub async fn apply_login_side_effects(state: &DaemonState, login: &AuthLoginResult) {
    *state.device_id.lock().unwrap() = Some(login.device_id.clone());
    *state.device_private_key.lock().unwrap() = Some(login.device_private_key);
    *state.db_encryption_key.lock().unwrap() = login.db_encryption_key;

    ensure_nagato_ingress_started(state, login).await;
    ensure_realtime_sync_started(state, login).await;

    let sync_context = SyncContext {
        access_token: login.access_token.clone(),
        user_id: login.user_id.clone(),
        device_id: login.device_id.clone(),
    };
    state.toshinori.set_context(sync_context.clone()).await;
    state.message_sync.set_context(sync_context.clone()).await;
    let realtime_syncer = { state.realtime_message_sync.read().await.clone() };
    if let Some(syncer) = realtime_syncer {
        syncer.set_context(sync_context).await;
    }
}

/// Clear sync contexts after logout.
pub async fn clear_login_side_effects(state: &DaemonState) {
    state.toshinori.clear_context().await;
    state.message_sync.clear_context().await;

    let realtime_syncer = {
        let mut guard = state.realtime_message_sync.write().await;
        guard.take()
    };
    if let Some(syncer) = realtime_syncer {
        syncer.clear_context().await;
    }
    state.toshinori.clear_realtime_message_syncer().await;

    if let Some(mut child) = state.nagato_process.lock().unwrap().take() {
        terminate_child(&mut child, "nagato");
    }
    if let Some(mut child) = state.falco_process.lock().unwrap().take() {
        terminate_child(&mut child, "falco");
    }

    for socket_path in [state.paths.nagato_socket_file(), state.paths.falco_socket_file()] {
        if socket_path.exists() {
            if let Err(err) = std::fs::remove_file(&socket_path) {
                warn!(
                    socket = %socket_path.display(),
                    error = %err,
                    "Failed removing sidecar socket during logout cleanup"
                );
            }
        }
    }

    state.ably_broker_cache.clear().await;
    info!("Stopped Ably sidecars and cleared broker cache after logout");
}

async fn ensure_realtime_sync_started(state: &DaemonState, login: &AuthLoginResult) {
    if state.ably_broker_falco_token.is_empty() {
        warn!("Falco broker token missing; Ably hot-path sync remains disabled");
        return;
    }

    if state.realtime_message_sync.read().await.is_some() {
        return;
    }

    let falco_socket_path = state.paths.falco_socket_file();
    if !falco_socket_path.exists() {
        match start_falco_sidecar(
            &state.paths,
            &login.device_id,
            &state.ably_broker_falco_token,
            &state.config.log_level,
            Duration::from_secs(5),
            "auth_login",
        )
        .await
        {
            Ok(child) => {
                let mut process_guard = state.falco_process.lock().unwrap();
                if let Some(mut existing) = process_guard.take() {
                    terminate_child(&mut existing, "falco");
                }
                *process_guard = Some(child);
                info!(
                    socket = %falco_socket_path.display(),
                    "Started Falco sidecar after login for Ably hot-path sync"
                );
            }
            Err(err) => {
                warn!(
                    error = %err,
                    "Failed to start Falco sidecar after login; Ably hot-path sync remains disabled"
                );
                return;
            }
        }
    }

    if let Err(err) = ensure_socket_connectable(&falco_socket_path).await {
        warn!(
            socket = %falco_socket_path.display(),
            error = %err,
            "Falco socket unavailable after login; Ably hot-path sync remains disabled"
        );
        return;
    }

    let syncer = Arc::new(AblyRealtimeSyncer::new(
        AblySyncConfig::default(),
        state.armin.clone(),
        state.db_encryption_key.clone(),
        falco_socket_path,
    ));

    let mut guard = state.realtime_message_sync.write().await;
    if guard.is_some() {
        return;
    }
    *guard = Some(syncer.clone());
    drop(guard);

    // Install into Toshinori and then start worker.
    state
        .toshinori
        .set_realtime_message_syncer(syncer.clone())
        .await;
    syncer.start();
    info!("Initialized Ably hot-path message sync worker after login");
}

async fn ensure_nagato_ingress_started(state: &DaemonState, login: &AuthLoginResult) {
    if state.ably_broker_nagato_token.is_empty() {
        warn!("Nagato broker token missing; remote command ingress remains disabled");
        return;
    }

    let mut stale_child = None;
    let should_start = {
        let mut process_guard = state.nagato_process.lock().unwrap();
        match process_guard.as_mut() {
            Some(existing) => match existing.try_wait() {
                Ok(None) => false,
                Ok(Some(status)) => {
                    warn!(
                        status = %status,
                        "Nagato sidecar exited unexpectedly; restarting after login"
                    );
                    stale_child = process_guard.take();
                    true
                }
                Err(err) => {
                    warn!(
                        error = %err,
                        "Failed to inspect Nagato sidecar state; restarting after login"
                    );
                    stale_child = process_guard.take();
                    true
                }
            },
            None => true,
        }
    };

    if let Some(mut child) = stale_child {
        terminate_child(&mut child, "nagato");
    }

    if !should_start {
        return;
    }

    match start_nagato_sidecar(
        state.paths.as_ref(),
        &login.device_id,
        &state.ably_broker_nagato_token,
        &state.config.log_level,
        Duration::from_secs(1),
        "auth_login",
    )
    .await
    {
        Ok(child) => {
            *state.nagato_process.lock().unwrap() = Some(child);
            info!("Started Nagato sidecar after login for remote command ingress");
        }
        Err(err) => {
            warn!(
                error = %err,
                "Failed to start Nagato sidecar after login; remote command ingress remains disabled"
            );
        }
    }
}
