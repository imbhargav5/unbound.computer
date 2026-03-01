//! Shared auth side effects for daemon state updates.

use crate::app::ably_sidecar::{ensure_daemon_ably_socket_connectable, start_daemon_ably_sidecar};
use crate::app::falco_sidecar::{ensure_socket_connectable, start_falco_sidecar, terminate_child};
use crate::app::nagato_sidecar::start_nagato_sidecar;
use crate::app::sidecar_logs::{
    attach_sidecar_log_streams, reap_sidecar_log_tasks, replace_sidecar_log_tasks,
};
use crate::app::DaemonState;
use agent_session_sqlite_persist_core::{CodingSessionStatus, SessionId, SessionWriter};
use sha2::{Digest, Sha256};
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;
use session_sync_sink::{AblyRealtimeSyncer, AblyRuntimeStatusSyncer, AblySyncConfig, SyncContext};
use tracing::{debug, info, warn};
use auth_engine::AuthLoginResult;

const DAEMON_PRESENCE_EVENT: &str = "daemon.presence.v1";

/// Apply in-memory cache updates and sync contexts after successful login.
pub async fn apply_login_side_effects(state: &DaemonState, login: &AuthLoginResult) {
    *state.device_id.lock().unwrap() = Some(login.device_id.clone());
    *state.device_private_key.lock().unwrap() = Some(login.device_private_key);
    *state.db_encryption_key.lock().unwrap() = login.db_encryption_key;

    let sidecars_ready = ensure_sidecars_for_session(state, &login.user_id, &login.device_id).await;
    if !sidecars_ready {
        warn!("daemon-ably sidecar unavailable after login; Ably sidecars remain disabled");
    }

    let sync_context = SyncContext {
        access_token: login.access_token.clone(),
        user_id: login.user_id.clone(),
        device_id: login.device_id.clone(),
    };
    state.sync_sink.set_context(sync_context.clone()).await;
    state.message_sync.set_context(sync_context.clone()).await;
    let realtime_syncer = { state.realtime_message_sync.read().await.clone() };
    if let Some(syncer) = realtime_syncer {
        syncer.set_context(sync_context.clone()).await;
    }
    let runtime_status_syncer = { state.realtime_runtime_status_sync.read().await.clone() };
    if let Some(syncer) = runtime_status_syncer {
        syncer.set_context(sync_context).await;
    }
}

/// Clear sync contexts after logout.
pub async fn clear_login_side_effects(state: &DaemonState) {
    mark_active_sessions_not_available(state);
    state.sync_sink.clear_context().await;
    state.message_sync.clear_context().await;
    if let Some(syncer) = state.realtime_message_sync.read().await.clone() {
        syncer.clear_context().await;
    }
    if let Some(syncer) = state.realtime_runtime_status_sync.read().await.clone() {
        syncer.clear_context().await;
    }
    stop_managed_sidecars(state, true).await;
}

fn mark_active_sessions_not_available(state: &DaemonState) {
    let device_id = {
        let guard = state.device_id.lock().unwrap();
        guard.clone()
    };

    let Some(device_id) = device_id else {
        warn!("Skipping runtime status transition to not-available on logout: device_id missing");
        return;
    };

    let active_sessions: Vec<String> = {
        let guard = state.claude_processes.lock().unwrap();
        guard.keys().cloned().collect()
    };

    for session_id in active_sessions {
        let armin_session_id = SessionId::from_string(session_id);
        if let Err(err) = state.armin.update_runtime_status(
            &armin_session_id,
            &device_id,
            CodingSessionStatus::NotAvailable,
            None,
        ) {
            warn!(
                session_id = armin_session_id.as_str(),
                error = %err,
                "Failed to mark session as not-available during logout"
            );
        }
    }
}

/// Reconcile managed sidecars with the current auth session.
///
/// Returns `true` when sidecars are healthy or intentionally stopped due to no auth context.
pub async fn reconcile_sidecars_with_auth(state: &DaemonState) -> bool {
    match state.auth_runtime.current_sync_context() {
        Ok(Some(sync)) => {
            let ready = ensure_sidecars_for_session(state, &sync.user_id, &sync.device_id).await;
            if ready {
                let sync_context = SyncContext {
                    access_token: sync.access_token,
                    user_id: sync.user_id,
                    device_id: sync.device_id,
                };
                state.sync_sink.set_context(sync_context.clone()).await;
                state.message_sync.set_context(sync_context.clone()).await;
                if let Some(syncer) = state.realtime_message_sync.read().await.clone() {
                    syncer.set_context(sync_context.clone()).await;
                }
                if let Some(syncer) = state.realtime_runtime_status_sync.read().await.clone() {
                    syncer.set_context(sync_context.clone()).await;
                }
            }
            ready
        }
        Ok(None) => {
            state.sync_sink.clear_context().await;
            state.message_sync.clear_context().await;
            if let Some(syncer) = state.realtime_message_sync.read().await.clone() {
                syncer.clear_context().await;
            }
            if let Some(syncer) = state.realtime_runtime_status_sync.read().await.clone() {
                syncer.clear_context().await;
            }
            stop_managed_sidecars(state, false).await;
            true
        }
        Err(err) => {
            warn!(
                error = %err,
                "Failed to resolve auth sync context while reconciling sidecars"
            );
            false
        }
    }
}

async fn ensure_sidecars_for_session(state: &DaemonState, user_id: &str, device_id: &str) -> bool {
    let _lifecycle_guard = state.sidecar_lifecycle_lock.lock().await;

    let daemon_ably_ready = ensure_daemon_ably_started_locked(state, user_id, device_id).await;
    if !daemon_ably_ready {
        return false;
    }

    let nagato_ready = ensure_nagato_ingress_started_locked(state, device_id).await;
    let realtime_ready = ensure_realtime_sync_started_locked(state, device_id).await;
    nagato_ready && realtime_ready
}

async fn ensure_realtime_sync_started_locked(state: &DaemonState, device_id: &str) -> bool {
    if let Err(err) = ensure_daemon_ably_socket_connectable(&state.paths.ably_socket_file()).await {
        warn!(
            error = %err,
            "daemon-ably socket unavailable; Ably hot-path sync remains disabled"
        );
        return false;
    }

    let falco_socket_path = state.paths.falco_socket_file();
    let mut stale_child = None;
    let should_start = {
        let mut process_guard = state.falco_process.lock().unwrap();
        match process_guard.as_mut() {
            Some(existing) => match existing.try_wait() {
                Ok(None) => false,
                Ok(Some(status)) => {
                    warn!(
                        status = %status,
                        "Falco sidecar exited unexpectedly; restarting"
                    );
                    stale_child = process_guard.take();
                    true
                }
                Err(err) => {
                    warn!(
                        error = %err,
                        "Failed to inspect Falco sidecar state; restarting"
                    );
                    stale_child = process_guard.take();
                    true
                }
            },
            None => true,
        }
    };

    if let Some(mut child) = stale_child {
        terminate_child(&mut child, "falco");
        reap_sidecar_log_tasks(state, "falco");
    }

    if should_start {
        remove_stale_socket(&falco_socket_path, "falco");
        match start_falco_sidecar(
            &state.paths,
            device_id,
            &state.config.log_level,
            Duration::from_secs(5),
            "supervisor",
        )
        .await
        {
            Ok(mut child) => {
                let tasks = attach_sidecar_log_streams(&mut child, "falco", "supervisor");
                let mut process_guard = state.falco_process.lock().unwrap();
                if let Some(mut existing) = process_guard.take() {
                    terminate_child(&mut existing, "falco");
                }
                *process_guard = Some(child);
                drop(process_guard);
                replace_sidecar_log_tasks(state, "falco", tasks);
                info!(
                    socket = %falco_socket_path.display(),
                    "Started Falco sidecar for Ably hot-path sync"
                );
            }
            Err(err) => {
                warn!(
                    error = %err,
                    "Failed to start Falco sidecar; Ably hot-path sync remains disabled"
                );
                return false;
            }
        }
    }

    if let Err(err) = ensure_socket_connectable(&falco_socket_path).await {
        warn!(
            socket = %falco_socket_path.display(),
            error = %err,
            "Falco socket unavailable; restarting sidecar"
        );
        if let Some(mut child) = state.falco_process.lock().unwrap().take() {
            terminate_child(&mut child, "falco");
            reap_sidecar_log_tasks(state, "falco");
        }
        remove_stale_socket(&falco_socket_path, "falco");
        match start_falco_sidecar(
            &state.paths,
            device_id,
            &state.config.log_level,
            Duration::from_secs(5),
            "socket_recovery",
        )
        .await
        {
            Ok(mut child) => {
                let tasks = attach_sidecar_log_streams(&mut child, "falco", "socket_recovery");
                *state.falco_process.lock().unwrap() = Some(child);
                replace_sidecar_log_tasks(state, "falco", tasks);
            }
            Err(restart_err) => {
                warn!(
                    error = %restart_err,
                    "Failed to restart Falco sidecar after socket failure"
                );
                return false;
            }
        }
        if let Err(recheck_err) = ensure_socket_connectable(&falco_socket_path).await {
            warn!(
                socket = %falco_socket_path.display(),
                error = %recheck_err,
                "Falco socket still unavailable after restart"
            );
            return false;
        }
    }

    let message_syncer = Arc::new(AblyRealtimeSyncer::new(
        AblySyncConfig::default(),
        state.armin.clone(),
        state.db_encryption_key.clone(),
        falco_socket_path.clone(),
    ));
    let runtime_status_syncer = Arc::new(AblyRuntimeStatusSyncer::new(falco_socket_path));

    let install_message_syncer = {
        let mut guard = state.realtime_message_sync.write().await;
        if guard.is_none() {
            *guard = Some(message_syncer.clone());
            true
        } else {
            false
        }
    };

    let install_runtime_status_syncer = {
        let mut guard = state.realtime_runtime_status_sync.write().await;
        if guard.is_none() {
            *guard = Some(runtime_status_syncer.clone());
            true
        } else {
            false
        }
    };

    if !install_message_syncer && !install_runtime_status_syncer {
        return true;
    }

    // Install into session sync sink and then start worker.
    if install_message_syncer {
        state
            .sync_sink
            .set_realtime_message_syncer(message_syncer.clone())
            .await;
        message_syncer.start();
    }
    if install_runtime_status_syncer {
        state
            .sync_sink
            .set_realtime_runtime_status_syncer(runtime_status_syncer.clone())
            .await;
        runtime_status_syncer.start();
    }
    info!("Initialized Ably hot-path sync workers");
    true
}

async fn ensure_nagato_ingress_started_locked(state: &DaemonState, device_id: &str) -> bool {
    if let Err(err) = ensure_daemon_ably_socket_connectable(&state.paths.ably_socket_file()).await {
        warn!(
            error = %err,
            "daemon-ably socket unavailable; remote command ingress remains disabled"
        );
        return false;
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
        reap_sidecar_log_tasks(state, "nagato");
    }

    if !should_start {
        return true;
    }

    match start_nagato_sidecar(
        state.paths.as_ref(),
        device_id,
        &state.config.log_level,
        Duration::from_secs(1),
        "supervisor",
    )
    .await
    {
        Ok(mut child) => {
            let tasks = attach_sidecar_log_streams(&mut child, "nagato", "supervisor");
            *state.nagato_process.lock().unwrap() = Some(child);
            replace_sidecar_log_tasks(state, "nagato", tasks);
            info!("Started Nagato sidecar for remote command ingress");
            true
        }
        Err(err) => {
            warn!(
                error = %err,
                "Failed to start Nagato sidecar; remote command ingress remains disabled"
            );
            false
        }
    }
}

async fn ensure_daemon_ably_started_locked(
    state: &DaemonState,
    user_id: &str,
    device_id: &str,
) -> bool {
    if state.ably_broker_falco_token.is_empty() || state.ably_broker_nagato_token.is_empty() {
        warn!("Ably broker tokens missing; daemon-ably sidecar remains disabled");
        return false;
    }

    let ably_socket_path = state.paths.ably_socket_file();
    let presence_channel = format!("presence:{}", user_id.to_ascii_lowercase());
    let user_id_hash = hash_identifier_for_observability(user_id);
    let device_id_hash = hash_identifier_for_observability(device_id);
    info!(
        runtime = "sidecar",
        component = "sidecar.daemon-ably",
        event_code = "daemon.presence.channel.configured",
        user_id_hash = %user_id_hash,
        device_id_hash = %device_id_hash,
        presence_channel = %presence_channel,
        presence_event = DAEMON_PRESENCE_EVENT,
        "Configured daemon presence channel"
    );

    let mut stale_child = None;
    let mut should_start = {
        let mut process_guard = state.daemon_ably_process.lock().unwrap();
        match process_guard.as_mut() {
            Some(existing) => match existing.try_wait() {
                Ok(None) => false,
                Ok(Some(status)) => {
                    warn!(
                        status = %status,
                        "daemon-ably sidecar exited unexpectedly; restarting after login"
                    );
                    stale_child = process_guard.take();
                    true
                }
                Err(err) => {
                    warn!(
                        error = %err,
                        "Failed to inspect daemon-ably sidecar state; restarting after login"
                    );
                    stale_child = process_guard.take();
                    true
                }
            },
            None => true,
        }
    };

    if let Some(mut child) = stale_child {
        terminate_child(&mut child, "daemon-ably");
        reap_sidecar_log_tasks(state, "daemon-ably");
    }

    if !should_start {
        if let Err(err) = ensure_daemon_ably_socket_connectable(&ably_socket_path).await {
            warn!(
                socket = %ably_socket_path.display(),
                error = %err,
                "daemon-ably process running but socket is unavailable; restarting"
            );
            let mut process_guard = state.daemon_ably_process.lock().unwrap();
            if let Some(mut existing) = process_guard.take() {
                terminate_child(&mut existing, "daemon-ably");
                drop(process_guard);
                reap_sidecar_log_tasks(state, "daemon-ably");
            } else {
                drop(process_guard);
            }
            should_start = true;
        }
    }

    if should_start {
        state.ably_broker_cache.clear().await;
        debug!("Cleared Ably broker token cache before daemon-ably restart");
        info!(
            runtime = "sidecar",
            component = "sidecar.daemon-ably",
            event_code = "daemon.presence.sidecar.starting",
            user_id_hash = %user_id_hash,
            device_id_hash = %device_id_hash,
            presence_channel = %presence_channel,
            presence_event = DAEMON_PRESENCE_EVENT,
            "Starting daemon-ably sidecar for presence transport"
        );
        if ably_socket_path.exists() {
            if let Err(err) = std::fs::remove_file(&ably_socket_path) {
                warn!(
                    socket = %ably_socket_path.display(),
                    error = %err,
                    "Failed removing stale daemon-ably socket before restart"
                );
            }
        }

        match start_daemon_ably_sidecar(
            state.paths.as_ref(),
            user_id,
            device_id,
            &state.ably_broker_falco_token,
            &state.ably_broker_nagato_token,
            &state.config.log_level,
            Duration::from_secs(5),
            "supervisor",
        )
        .await
        {
            Ok(mut child) => {
                let tasks = attach_sidecar_log_streams(&mut child, "daemon-ably", "supervisor");
                *state.daemon_ably_process.lock().unwrap() = Some(child);
                replace_sidecar_log_tasks(state, "daemon-ably", tasks);
                info!(
                    runtime = "sidecar",
                    component = "sidecar.daemon-ably",
                    event_code = "daemon.presence.sidecar.started",
                    user_id_hash = %user_id_hash,
                    device_id_hash = %device_id_hash,
                    presence_channel = %presence_channel,
                    presence_event = DAEMON_PRESENCE_EVENT,
                    "Started daemon-ably sidecar after login"
                );
            }
            Err(err) => {
                warn!(
                    runtime = "sidecar",
                    component = "sidecar.daemon-ably",
                    event_code = "daemon.presence.sidecar.start_failed",
                    user_id_hash = %user_id_hash,
                    device_id_hash = %device_id_hash,
                    presence_channel = %presence_channel,
                    presence_event = DAEMON_PRESENCE_EVENT,
                    error = %err,
                    "Failed to start daemon-ably sidecar after login"
                );
                return false;
            }
        }
    }

    if let Err(err) = ensure_daemon_ably_socket_connectable(&ably_socket_path).await {
        warn!(
            socket = %ably_socket_path.display(),
            error = %err,
            "daemon-ably socket unavailable after startup"
        );
        return false;
    }

    true
}

async fn stop_managed_sidecars(state: &DaemonState, clear_broker_cache: bool) {
    let _lifecycle_guard = state.sidecar_lifecycle_lock.lock().await;
    stop_managed_sidecars_locked(state, clear_broker_cache).await;
}

async fn stop_managed_sidecars_locked(state: &DaemonState, clear_broker_cache: bool) {
    let realtime_message_syncer = {
        let mut guard = state.realtime_message_sync.write().await;
        guard.take()
    };
    if let Some(syncer) = realtime_message_syncer {
        syncer.clear_context().await;
    }
    state.sync_sink.clear_realtime_message_syncer().await;

    let realtime_runtime_status_syncer = {
        let mut guard = state.realtime_runtime_status_sync.write().await;
        guard.take()
    };
    if let Some(syncer) = realtime_runtime_status_syncer {
        syncer.clear_context().await;
    }
    state.sync_sink.clear_realtime_runtime_status_syncer().await;

    if let Some(mut child) = state.nagato_process.lock().unwrap().take() {
        terminate_child(&mut child, "nagato");
    }
    reap_sidecar_log_tasks(state, "nagato");

    if let Some(mut child) = state.falco_process.lock().unwrap().take() {
        terminate_child(&mut child, "falco");
    }
    reap_sidecar_log_tasks(state, "falco");

    if let Some(mut child) = state.daemon_ably_process.lock().unwrap().take() {
        terminate_child(&mut child, "daemon-ably");
    }
    reap_sidecar_log_tasks(state, "daemon-ably");

    for socket_path in state.paths.sidecar_socket_files() {
        remove_stale_socket(&socket_path, "managed sidecar");
    }

    if clear_broker_cache {
        state.ably_broker_cache.clear().await;
        info!("Stopped Ably sidecars and cleared broker cache after logout");
    }
}

fn remove_stale_socket(path: &Path, scope: &str) {
    if !path.exists() {
        return;
    }

    if let Err(err) = std::fs::remove_file(path) {
        warn!(
            socket = %path.display(),
            scope = scope,
            error = %err,
            "Failed removing stale sidecar socket"
        );
    }
}

fn hash_identifier_for_observability(value: &str) -> String {
    let normalized = value.trim().to_ascii_lowercase();
    if normalized.is_empty() {
        return "unknown".to_string();
    }

    let mut hasher = Sha256::new();
    hasher.update(normalized.as_bytes());
    let digest = hasher.finalize();
    format!("sha256:{:x}", digest)
}
