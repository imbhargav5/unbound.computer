//! Daemon initialization.

use crate::app::falco_sidecar::terminate_child;
use crate::app::nagato_server::spawn_nagato_server;
use crate::app::sidecar_logs::reap_all_sidecar_log_tasks;
use crate::app::sidecar_supervisor::spawn_sidecar_supervisor;
use crate::app::{DaemonState, ManagedAblyBrokerState, StartupStatusWriter};
use crate::armin_adapter::create_daemon_armin;
use crate::auth::common::{reconcile_sidecars_with_auth, shutdown_hot_path_syncers};
use crate::ipc::register_handlers;
use crate::remote_command_handler::idempotency::IdempotencyStore;
use crate::remote_command_handler::runtime::start_billing_quota_refresh_loop;
use crate::utils::{load_session_secrets_from_supabase, SessionSecretCache};
use agent_session_sqlite_persist_core::{SessionId, SessionReader};
use auth_engine::{DaemonAuthRuntime, SessionManager, SupabaseClient};
use daemon_config_and_utils::{force_flush, shutdown};
use daemon_config_and_utils::{Config, Paths};
use daemon_database::AsyncDatabase;
use daemon_ipc::IpcServer;
use daemon_storage::create_secrets_manager;
use message_sync_retriable_worker::SessionSyncService;
use message_sync_retriable_worker::{MessageSyncWorker, MessageSyncWorkerConfig};
use safe_file_ops::SafeFileOps;
use session_sync_sink::{SessionMetadata, SessionMetadataProvider, SessionSyncSink, SyncContext};
use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, Mutex};
use tokio::task::JoinHandle;
use tokio::time::{sleep, Duration, Instant};
use tracing::{debug, info, warn};

struct ArminSessionMetadataProvider {
    armin: Arc<crate::armin_adapter::DaemonArmin>,
}

impl SessionMetadataProvider for ArminSessionMetadataProvider {
    fn get_session_metadata(&self, session_id: &str) -> Option<SessionMetadata> {
        let session_id = SessionId::from_string(session_id);
        let session = self.armin.get_session(&session_id).ok().flatten()?;

        Some(SessionMetadata {
            repository_id: session.repository_id.as_str().to_string(),
            title: Some(session.title),
            current_branch: None,
            working_directory: None,
            is_worktree: session.is_worktree,
            worktree_path: session.worktree_path,
        })
    }
}

/// Run the daemon.
pub async fn run_daemon(
    config: Config,
    paths: Paths,
    _foreground: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let startup_status = StartupStatusWriter::new(paths.startup_status_file());
    startup_status.clear();
    startup_status.update("critical_bootstrap", "Checking daemon singleton state");
    enforce_singleton_and_cleanup(&paths).await?;

    info!("Starting Unbound daemon");

    // Log config values to verify compile-time env vars
    info!(
        supabase_url = %config.supabase_url,
        supabase_key_prefix = %&config.supabase_publishable_key[..config.supabase_publishable_key.len().min(20)],
        "Configuration loaded"
    );

    startup_status.update("critical_bootstrap", "Ensuring runtime directories exist");
    paths.ensure_dirs()?;

    startup_status.update("critical_bootstrap", "Writing daemon PID file");
    let pid = std::process::id();
    std::fs::write(paths.pid_file(), pid.to_string())?;
    info!(pid = pid, "Daemon started");

    startup_status.update("critical_bootstrap", "Initializing IPC server");
    let ipc_server = IpcServer::new(&paths.socket_file().to_string_lossy());

    let sync_sink = Arc::new(SessionSyncSink::new(
        &config.supabase_url,
        &config.supabase_publishable_key,
        tokio::runtime::Handle::current(),
    ));

    startup_status.update("critical_bootstrap", "Initializing Armin session engine");
    let armin = create_daemon_armin(
        &paths.database_file(),
        ipc_server.subscriptions().clone(),
        Some(sync_sink.clone()),
    )
    .map_err(|e| format!("Failed to initialize Armin: {}", e))?;
    info!(
        path = %paths.database_file().display(),
        "Armin session engine initialized"
    );

    sync_sink
        .set_metadata_provider(Arc::new(ArminSessionMetadataProvider {
            armin: armin.clone(),
        }))
        .await;

    startup_status.update("critical_bootstrap", "Opening async database");
    let db = AsyncDatabase::open(&paths.database_file())
        .await
        .map_err(|e| format!("Failed to open async database: {}", e))?;
    info!("Async database initialized");

    startup_status.update("critical_bootstrap", "Initializing secure storage");
    let secrets = create_secrets_manager()?;
    info!("Secure storage initialized");
    let secrets_arc = Arc::new(Mutex::new(secrets));

    let supabase_client = Arc::new(SupabaseClient::new(
        &config.supabase_url,
        &config.supabase_publishable_key,
    ));
    info!("Supabase client initialized");

    startup_status.update("critical_bootstrap", "Creating auth runtime");
    let auth_runtime = Arc::new(DaemonAuthRuntime::new(
        SessionManager::new(
            create_secrets_manager()?,
            &config.supabase_url,
            &config.supabase_publishable_key,
        ),
        supabase_client.clone(),
        secrets_arc.clone(),
        config.supabase_url.clone(),
        config.web_app_url.clone(),
    ));

    startup_status.update("critical_bootstrap", "Loading persisted device identity");
    let (db_encryption_key, device_id, device_private_key) = {
        let secrets = secrets_arc.lock().unwrap();

        let db_encryption_key = match secrets.get_database_encryption_key() {
            Ok(Some(key)) => {
                info!("Device private key found and database encryption key cached");
                Some(key)
            }
            Ok(None) => {
                warn!("No device private key found. Please set up device trust in the macOS app first, or the CLI will generate a new key for standalone usage.");
                None
            }
            Err(e) => {
                warn!("Could not get database encryption key: {}", e);
                None
            }
        };

        let device_id = secrets.get_device_id().ok().flatten();
        let device_private_key = secrets
            .get_device_private_key()
            .ok()
            .flatten()
            .and_then(|k| k.try_into().ok());

        (db_encryption_key, device_id, device_private_key)
    };
    let db_encryption_key_arc = Arc::new(Mutex::new(db_encryption_key));

    if device_id.is_some() && device_private_key.is_some() {
        info!("Device identity loaded for multi-device session secret distribution");
    }

    let device_id_arc = Arc::new(Mutex::new(device_id));
    let device_private_key_arc = Arc::new(Mutex::new(device_private_key));

    let session_secret_cache = SessionSecretCache::new();

    let session_sync = Arc::new(SessionSyncService::new(
        supabase_client.clone(),
        db.clone(),
        secrets_arc.clone(),
        device_id_arc.clone(),
        device_private_key_arc.clone(),
        session_secret_cache.inner(),
    ));

    let armin_handle: message_sync_retriable_worker::ArminHandle = armin.clone();
    let message_sync = Arc::new(MessageSyncWorker::new(
        MessageSyncWorkerConfig::default(),
        &config.supabase_url,
        &config.supabase_publishable_key,
        armin_handle,
        db_encryption_key_arc.clone(),
    ));

    sync_sink.set_message_syncer(message_sync.clone()).await;
    message_sync.start();

    startup_status.update("critical_bootstrap", "Constructing daemon state");
    let safe_file_ops = Arc::new(SafeFileOps::with_defaults());
    let state = DaemonState {
        config: Arc::new(config),
        paths: Arc::new(paths.clone()),
        db,
        secrets: secrets_arc,
        claude_processes: Arc::new(Mutex::new(HashMap::new())),
        terminal_processes: Arc::new(Mutex::new(HashMap::new())),
        db_encryption_key: db_encryption_key_arc,
        subscriptions: ipc_server.subscriptions().clone(),
        session_secret_cache,
        supabase_client,
        auth_runtime,
        device_id: device_id_arc,
        device_private_key: device_private_key_arc,
        session_sync,
        sync_sink,
        message_sync,
        realtime_message_sync: Arc::new(tokio::sync::RwLock::new(None)),
        realtime_runtime_status_sync: Arc::new(tokio::sync::RwLock::new(None)),
        falco_process: Arc::new(Mutex::new(None)),
        nagato_process: Arc::new(Mutex::new(None)),
        daemon_ably_process: Arc::new(Mutex::new(None)),
        sidecar_log_tasks: Arc::new(Mutex::new(HashMap::new())),
        remote_command_idempotency: Arc::new(Mutex::new(IdempotencyStore::default())),
        nagato_shutdown_tx: Arc::new(Mutex::new(None)),
        nagato_server_task: Arc::new(Mutex::new(None)),
        sidecar_supervisor_shutdown_tx: Arc::new(Mutex::new(None)),
        sidecar_supervisor_task: Arc::new(Mutex::new(None)),
        sidecar_lifecycle_lock: Arc::new(tokio::sync::Mutex::new(())),
        ably_broker: Arc::new(tokio::sync::Mutex::new(ManagedAblyBrokerState::default())),
        armin,
        safe_file_ops,
        billing_quota_cache: Arc::new(Mutex::new(Default::default())),
        billing_quota_refresh_runtime: Arc::new(Mutex::new(None)),
    };

    register_handlers(&ipc_server, state.clone()).await;

    startup_status.update("critical_bootstrap", "Starting IPC server");
    let socket_path = paths.socket_file();
    let mut ipc_task = tokio::spawn(async move { ipc_server.run().await });
    if let Err(error) =
        wait_for_ipc_socket_ready(&socket_path, &mut ipc_task, &startup_status).await
    {
        cleanup_runtime_workers(&state).await;
        startup_status.update("critical_bootstrap_failed", &error.to_string());
        remove_runtime_files(&paths);
        force_flush();
        shutdown();
        return Err(error);
    }
    startup_status.update("socket_ready", "Daemon IPC socket is listening");

    let billing_quota_refresh_runtime = start_billing_quota_refresh_loop(state.clone());
    *state.billing_quota_refresh_runtime.lock().unwrap() = Some(billing_quota_refresh_runtime);

    {
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let task = spawn_nagato_server(state.clone(), shutdown_rx);
        *state.nagato_shutdown_tx.lock().unwrap() = Some(shutdown_tx);
        *state.nagato_server_task.lock().unwrap() = Some(task);
    }

    {
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let task = spawn_sidecar_supervisor(state.clone(), shutdown_rx);
        *state.sidecar_supervisor_shutdown_tx.lock().unwrap() = Some(shutdown_tx);
        *state.sidecar_supervisor_task.lock().unwrap() = Some(task);
    }

    let post_listen_task = spawn_post_listen_bootstrap(state.clone(), startup_status.clone());
    let runtime_state = state.clone();

    let server_result = match ipc_task.await {
        Ok(result) => result.map_err(|err| -> Box<dyn std::error::Error> { err.into() }),
        Err(err) => Err(format!("IPC server task join failed: {err}").into()),
    };

    post_listen_task.abort();
    let _ = post_listen_task.await;

    if let Some(shutdown_tx) = runtime_state.nagato_shutdown_tx.lock().unwrap().take() {
        let _ = shutdown_tx.send(());
    }
    let nagato_task = runtime_state.nagato_server_task.lock().unwrap().take();
    if let Some(task) = nagato_task {
        if let Err(err) = task.await {
            warn!(error = %err, "Nagato socket listener task join failed");
        }
    }
    if let Some(shutdown_tx) = runtime_state
        .sidecar_supervisor_shutdown_tx
        .lock()
        .unwrap()
        .take()
    {
        let _ = shutdown_tx.send(());
    }
    let supervisor_task = runtime_state.sidecar_supervisor_task.lock().unwrap().take();
    if let Some(task) = supervisor_task {
        if let Err(err) = task.await {
            warn!(error = %err, "Sidecar supervisor task join failed");
        }
    }

    shutdown_ably_broker(&runtime_state).await;

    runtime_state.sync_sink.clear_message_syncer().await;
    runtime_state.sync_sink.clear_metadata_provider().await;
    runtime_state.sync_sink.clear_context().await;
    runtime_state.message_sync.clear_context().await;
    runtime_state.message_sync.shutdown().await;

    let billing_quota_refresh_runtime = runtime_state
        .billing_quota_refresh_runtime
        .lock()
        .unwrap()
        .take();
    if let Some(runtime) = billing_quota_refresh_runtime {
        runtime.shutdown().await;
    }

    shutdown_hot_path_syncers(&runtime_state).await;
    runtime_state.sync_sink.shutdown().await;

    if let Some(mut child) = runtime_state.nagato_process.lock().unwrap().take() {
        terminate_child(&mut child, "nagato");
    }

    if let Some(mut child) = runtime_state.falco_process.lock().unwrap().take() {
        terminate_child(&mut child, "falco");
    }
    if let Some(mut child) = runtime_state.daemon_ably_process.lock().unwrap().take() {
        terminate_child(&mut child, "daemon-ably");
    }
    reap_all_sidecar_log_tasks(&runtime_state);

    startup_status.update("stopped", "Daemon shutdown complete");
    info!("Daemon stopped");
    force_flush();
    shutdown();

    remove_runtime_files(&paths);

    server_result
}

async fn enforce_singleton_and_cleanup(paths: &Paths) -> Result<(), Box<dyn std::error::Error>> {
    let socket_path = paths.socket_file();
    if socket_path.exists() {
        let client = daemon_ipc::IpcClient::new(&socket_path.to_string_lossy());
        if client.call_method(daemon_ipc::Method::Health).await.is_ok() {
            eprintln!(
                "Error: Daemon is already running. Use 'unbound daemon stop' to stop it first."
            );
            std::process::exit(1);
        }
        eprintln!("Removing stale socket file");
        let _ = std::fs::remove_file(&socket_path);
    }

    let pid_file = paths.pid_file();
    if pid_file.exists() {
        let _ = std::fs::remove_file(&pid_file);
    }

    Ok(())
}

async fn wait_for_ipc_socket_ready(
    socket_path: &Path,
    ipc_task: &mut JoinHandle<daemon_ipc::IpcResult<()>>,
    startup_status: &StartupStatusWriter,
) -> Result<(), Box<dyn std::error::Error>> {
    let deadline = Instant::now() + Duration::from_secs(5);

    loop {
        if socket_path.exists() {
            return Ok(());
        }

        if ipc_task.is_finished() {
            let result = ipc_task
                .await
                .map_err(|err| format!("IPC server task join failed before socket ready: {err}"))?;
            return result.map_err(|err| err.into());
        }

        if Instant::now() >= deadline {
            let message = format!(
                "Timed out waiting for IPC socket {} to become ready",
                socket_path.display()
            );
            startup_status.update("critical_bootstrap_failed", &message);
            return Err(message.into());
        }

        sleep(Duration::from_millis(25)).await;
    }
}

fn spawn_post_listen_bootstrap(
    state: DaemonState,
    startup_status: StartupStatusWriter,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        startup_status.update("post_listen_bootstrap", "Validating persisted auth session");

        match state.auth_runtime.validate_session_on_startup().await {
            Ok(true) => {
                info!("Existing session validated successfully");

                startup_status.update("post_listen_bootstrap", "Applying validated sync context");
                apply_startup_sync_context(&state).await;

                startup_status.update("post_listen_bootstrap", "Refreshing device capabilities");
                if let Err(error) = state.auth_runtime.refresh_device_capabilities().await {
                    warn!(
                        "Failed to refresh device capabilities on startup: {}",
                        error
                    );
                }

                spawn_post_auth_background_sync_tasks(state.clone());

                startup_status.update("post_listen_bootstrap", "Reconciling Ably sidecars");
                if !reconcile_sidecars_with_auth(&state).await {
                    warn!("Startup sidecar reconciliation failed; supervisor will retry");
                }
            }
            Ok(false) => {
                info!("No existing session to validate");
                startup_status.update(
                    "post_listen_bootstrap",
                    "No stored session found; continuing unauthenticated",
                );
            }
            Err(error) => {
                warn!(
                    "Session validation failed, user will need to re-authenticate: {}",
                    error
                );
                startup_status.update(
                    "post_listen_bootstrap",
                    "Stored session invalid; continuing unauthenticated",
                );
            }
        }

        startup_status.update("ready", "Post-listen bootstrap complete");
    })
}

async fn apply_startup_sync_context(state: &DaemonState) {
    let sync = match state.auth_runtime.current_sync_context() {
        Ok(Some(sync)) => sync,
        Ok(None) => return,
        Err(err) => {
            warn!(
                error = %err,
                "Failed to resolve startup auth sync context; Supabase sync remains disabled"
            );
            return;
        }
    };

    let sync_context = SyncContext {
        access_token: sync.access_token,
        user_id: sync.user_id,
        device_id: sync.device_id,
    };

    state.sync_sink.set_context(sync_context.clone()).await;
    state.message_sync.set_context(sync_context).await;
    info!("Initialized Supabase sync contexts from persisted auth session");
}

fn spawn_post_auth_background_sync_tasks(state: DaemonState) {
    let state_for_loading = state.clone();
    tokio::spawn(async move {
        match load_session_secrets_from_supabase(&state_for_loading).await {
            Ok(count) if count > 0 => info!("Loaded {} session secrets from Supabase", count),
            Ok(_) => debug!("No session secrets to load from Supabase"),
            Err(e) => warn!("Failed to load session secrets from Supabase: {}", e),
        }
    });

    let armin_ref = state.armin.clone();
    let session_sync_ref = state.session_sync.clone();
    tokio::spawn(async move {
        let pending = match armin_ref.get_sessions_pending_sync(1000) {
            Ok(p) => p,
            Err(e) => {
                warn!(
                    "Failed to query pending sync sessions for reconciliation: {}",
                    e
                );
                return;
            }
        };

        if pending.is_empty() {
            return;
        }

        info!(
            count = pending.len(),
            "Reconciling local sessions with Supabase before message sync"
        );

        let mut synced_repos = std::collections::HashSet::new();

        for session_pending in &pending {
            let session_id = session_pending.session_id.as_str();
            let session = match armin_ref.get_session(&session_pending.session_id) {
                Ok(Some(s)) => s,
                Ok(None) => {
                    warn!(
                        session_id,
                        "Pending sync session not found locally, skipping"
                    );
                    continue;
                }
                Err(e) => {
                    warn!(session_id, error = %e, "Failed to get session for reconciliation");
                    continue;
                }
            };

            let repo_id = session.repository_id.as_str().to_string();
            if !synced_repos.contains(&repo_id) {
                if let Err(e) = session_sync_ref.sync_repository(&repo_id).await {
                    warn!(session_id, repository_id = %repo_id, error = %e, "Failed to reconcile repository");
                }
                synced_repos.insert(repo_id);
            }

            if let Err(e) = session_sync_ref
                .sync_session(
                    session_id,
                    session.repository_id.as_str(),
                    session.status.as_str(),
                )
                .await
            {
                warn!(session_id, error = %e, "Failed to reconcile session to Supabase");
            }
        }
    });
}

async fn shutdown_ably_broker(state: &DaemonState) {
    let runtime = {
        let mut broker = state.ably_broker.lock().await;
        broker.cache_handle = None;
        broker.falco_token.clear();
        broker.nagato_token.clear();
        broker.runtime.take()
    };

    if let Some(runtime) = runtime {
        let _ = runtime.shutdown_tx.send(());
        if let Err(err) = runtime.task.await {
            warn!(error = %err, "Ably broker task join failed");
        }
    }
}

async fn cleanup_runtime_workers(state: &DaemonState) {
    state.sync_sink.clear_message_syncer().await;
    state.sync_sink.clear_metadata_provider().await;
    state.sync_sink.clear_context().await;
    state.message_sync.clear_context().await;
    state.message_sync.shutdown().await;
    state.sync_sink.shutdown().await;
}

fn remove_runtime_files(paths: &Paths) {
    let _ = std::fs::remove_file(paths.pid_file());
    let _ = std::fs::remove_file(paths.socket_file());
    for sidecar_socket in paths.sidecar_socket_files() {
        let _ = std::fs::remove_file(sidecar_socket);
    }
    let _ = std::fs::remove_file(paths.ably_auth_socket_file());
}
