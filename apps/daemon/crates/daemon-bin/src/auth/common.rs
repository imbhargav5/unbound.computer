//! Shared auth side effects for daemon state updates.

use crate::app::ably_sidecar::{ensure_daemon_ably_socket_connectable, start_daemon_ably_sidecar};
use crate::app::falco_sidecar::{ensure_socket_connectable, start_falco_sidecar, terminate_child};
use crate::app::nagato_sidecar::start_nagato_sidecar;
use crate::app::sidecar_logs::{
    attach_sidecar_log_streams, reap_sidecar_log_tasks, replace_sidecar_log_tasks,
};
use crate::app::DaemonState;
use std::path::Path;
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

    let sidecars_ready = ensure_sidecars_for_session(state, &login.user_id, &login.device_id).await;
    if !sidecars_ready {
        warn!("daemon-ably sidecar unavailable after login; Ably sidecars remain disabled");
    }

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
    stop_managed_sidecars(state, true).await;
}

/// Reconcile managed sidecars with the current auth session.
///
/// Returns `true` when sidecars are healthy or intentionally stopped due to no auth context.
pub async fn reconcile_sidecars_with_auth(state: &DaemonState) -> bool {
    match state.auth_runtime.current_sync_context() {
        Ok(Some(sync)) => ensure_sidecars_for_session(state, &sync.user_id, &sync.device_id).await,
        Ok(None) => {
            state.toshinori.clear_context().await;
            state.message_sync.clear_context().await;
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

    let syncer = Arc::new(AblyRealtimeSyncer::new(
        AblySyncConfig::default(),
        state.armin.clone(),
        state.db_encryption_key.clone(),
        falco_socket_path,
    ));

    let mut guard = state.realtime_message_sync.write().await;
    if guard.is_some() {
        return true;
    }
    *guard = Some(syncer.clone());
    drop(guard);

    // Install into Toshinori and then start worker.
    state
        .toshinori
        .set_realtime_message_syncer(syncer.clone())
        .await;
    syncer.start();
    info!("Initialized Ably hot-path message sync worker");
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
                info!("Started daemon-ably sidecar after login");
            }
            Err(err) => {
                warn!(
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
