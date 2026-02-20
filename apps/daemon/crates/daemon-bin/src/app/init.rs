//! Daemon initialization.

use crate::ably::start_ably_token_broker;
use crate::app::ably_sidecar::start_daemon_ably_sidecar;
use crate::app::falco_sidecar::{ensure_socket_connectable, start_falco_sidecar, terminate_child};
use crate::app::nagato_server::spawn_nagato_server;
use crate::app::nagato_sidecar::start_nagato_sidecar;
use crate::app::sidecar_logs::{
    attach_sidecar_log_streams, reap_all_sidecar_log_tasks, register_sidecar_log_tasks,
    SidecarLogTask,
};
use crate::app::sidecar_supervisor::spawn_sidecar_supervisor;
use crate::app::DaemonState;
use crate::armin_adapter::create_daemon_armin;
use crate::ipc::register_handlers;
use crate::itachi::idempotency::IdempotencyStore;
use crate::itachi::runtime::spawn_billing_quota_refresh_loop;
use crate::utils::{load_session_secrets_from_supabase, SessionSecretCache};
use armin::{SessionId, SessionReader};
use daemon_config_and_utils::{Config, Paths};
use daemon_database::AsyncDatabase;
use daemon_ipc::IpcServer;
use daemon_storage::create_secrets_manager;
use gyomei::Gyomei;
use levi::SessionSyncService;
use levi::{Levi, LeviConfig};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::process::Child;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use toshinori::{
    AblyRealtimeSyncer, AblyRuntimeStatusSyncer, AblySyncConfig, SessionMetadata,
    SessionMetadataProvider, SyncContext, ToshinoriSink,
};
use tracing::{debug, info, warn};
use ymir::{DaemonAuthRuntime, SessionManager, SupabaseClient};

const DAEMON_PRESENCE_EVENT: &str = "daemon.presence.v1";

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
    // Singleton enforcement: check if daemon is already running
    let socket_path = paths.socket_file();
    if socket_path.exists() {
        // Try to connect to existing daemon
        let client = daemon_ipc::IpcClient::new(&socket_path.to_string_lossy());
        if client.call_method(daemon_ipc::Method::Health).await.is_ok() {
            eprintln!(
                "Error: Daemon is already running. Use 'unbound daemon stop' to stop it first."
            );
            std::process::exit(1);
        }
        // Socket exists but daemon not responding - clean up stale socket
        eprintln!("Removing stale socket file");
        let _ = std::fs::remove_file(&socket_path);
    }

    // Clean up stale PID file if it exists
    let pid_file = paths.pid_file();
    if pid_file.exists() {
        let _ = std::fs::remove_file(&pid_file);
    }

    info!("Starting Unbound daemon");

    // Log config values to verify compile-time env vars
    info!(
        supabase_url = %config.supabase_url,
        supabase_key_prefix = %&config.supabase_publishable_key[..config.supabase_publishable_key.len().min(20)],
        "Configuration loaded"
    );

    // Ensure directories exist
    paths.ensure_dirs()?;

    // Write PID file
    let pid = std::process::id();
    std::fs::write(paths.pid_file(), pid.to_string())?;
    info!(pid = pid, "Daemon started");

    // Create IPC server first (we need subscriptions for Armin)
    let ipc_server = IpcServer::new(&paths.socket_file().to_string_lossy());

    // Create Toshinori sink for Supabase sync
    let toshinori = Arc::new(ToshinoriSink::new(
        &config.supabase_url,
        &config.supabase_publishable_key,
        tokio::runtime::Handle::current(),
    ));

    // Initialize Armin session engine with the daemon database
    // Armin now manages the complete schema (repositories, sessions, messages, etc.)
    let armin = create_daemon_armin(
        &paths.database_file(),
        ipc_server.subscriptions().clone(),
        Some(toshinori.clone()),
    )
    .map_err(|e| format!("Failed to initialize Armin: {}", e))?;
    info!(
        path = %paths.database_file().display(),
        "Armin session engine initialized"
    );

    toshinori
        .set_metadata_provider(Arc::new(ArminSessionMetadataProvider {
            armin: armin.clone(),
        }))
        .await;

    // Async database for operations not yet migrated to Armin
    let db = AsyncDatabase::open(&paths.database_file())
        .await
        .map_err(|e| format!("Failed to open async database: {}", e))?;
    info!("Async database initialized");

    // Initialize secure storage
    let secrets = create_secrets_manager()?;
    info!("Secure storage initialized");
    let secrets_arc = Arc::new(Mutex::new(secrets));

    // Create Supabase client for device management and secret distribution
    let supabase_client = Arc::new(SupabaseClient::new(
        &config.supabase_url,
        &config.supabase_publishable_key,
    ));
    info!("Supabase client initialized");

    // Unified auth runtime used by startup and IPC auth handlers.
    let auth_runtime = Arc::new(DaemonAuthRuntime::new(
        SessionManager::new(
            create_secrets_manager()?,
            &config.supabase_url,
            &config.supabase_publishable_key,
        ),
        supabase_client.clone(),
        secrets_arc.clone(),
        config.supabase_url.clone(),
    ));

    // Validate existing session on startup
    // If the user is already signed in, verify the session is still valid
    // and refresh if needed. If refresh fails, clean up the session.
    match auth_runtime.validate_session_on_startup().await {
        Ok(true) => {
            info!("Existing session validated successfully");
            if let Err(error) = auth_runtime.refresh_device_capabilities().await {
                warn!(
                    "Failed to refresh device capabilities on startup: {}",
                    error
                );
            }
        }
        Ok(false) => info!("No existing session to validate"),
        Err(e) => warn!(
            "Session validation failed, user will need to re-authenticate: {}",
            e
        ),
    }
    let startup_sync_context = match auth_runtime.current_sync_context() {
        Ok(sync_context) => sync_context,
        Err(err) => {
            warn!(
                error = %err,
                "Failed to resolve startup auth sync context; sidecars will remain disabled"
            );
            None
        }
    };
    let has_startup_auth_context = startup_sync_context.is_some();
    let startup_user_id = startup_sync_context
        .as_ref()
        .map(|sync| sync.user_id.clone());

    let mut ably_broker_runtime = Some(
        start_ably_token_broker(paths.ably_auth_socket_file(), auth_runtime.clone())
            .await
            .map_err(|err| format!("Failed to start Ably token broker: {}", err))?,
    );
    let ably_broker_nagato_token = ably_broker_runtime
        .as_ref()
        .map(|runtime| runtime.nagato_token.clone())
        .unwrap_or_default();
    let ably_broker_falco_token = ably_broker_runtime
        .as_ref()
        .map(|runtime| runtime.falco_token.clone())
        .unwrap_or_default();
    let ably_broker_cache = ably_broker_runtime
        .as_ref()
        .map(|runtime| runtime.cache_handle.clone())
        .expect("Ably broker runtime should always be available during init");

    // Resolve auth-dependent values from secure storage once at startup.
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

    // Keep a copy for sidecar startup decisions before moving into shared state.
    let local_device_id = device_id.clone();

    // Create shared Arc values for reuse
    let device_id_arc = Arc::new(Mutex::new(device_id));
    let device_private_key_arc = Arc::new(Mutex::new(device_private_key));

    // Create session secret cache (fast in-memory lookup)
    let session_secret_cache = SessionSecretCache::new();

    // Create session sync service (shares cache via inner Arc)
    let session_sync = Arc::new(SessionSyncService::new(
        supabase_client.clone(),
        db.clone(),
        secrets_arc.clone(),
        device_id_arc.clone(),
        device_private_key_arc.clone(),
        session_secret_cache.inner(),
    ));

    // Create Levi message sync worker
    let armin_handle: levi::ArminHandle = armin.clone();
    let message_sync = Arc::new(Levi::new(
        LeviConfig::default(),
        &config.supabase_url,
        &config.supabase_publishable_key,
        armin_handle,
        db_encryption_key_arc.clone(),
    ));

    let mut initial_daemon_ably_process: Option<Child> = None;
    let mut daemon_ably_ready = false;
    let daemon_ably_socket_path = paths.ably_socket_file();
    let mut initial_sidecar_log_tasks: HashMap<String, Vec<SidecarLogTask>> = HashMap::new();

    if has_startup_auth_context {
        match (startup_user_id.as_deref(), local_device_id.as_deref()) {
            (Some(user_id), Some(device_id)) => {
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
                // Strict ownership: never adopt a socket from another daemon instance.
                if daemon_ably_socket_path.exists() {
                    if let Err(err) = std::fs::remove_file(&daemon_ably_socket_path) {
                        warn!(
                            socket = %daemon_ably_socket_path.display(),
                            error = %err,
                            "Failed removing stale daemon-ably socket before startup"
                        );
                    }
                }
                match start_daemon_ably_sidecar(
                    &paths,
                    user_id,
                    device_id,
                    &ably_broker_falco_token,
                    &ably_broker_nagato_token,
                    &config.log_level,
                    Duration::from_secs(5),
                    "daemon_startup",
                )
                .await
                {
                    Ok(mut child) => {
                        let tasks =
                            attach_sidecar_log_streams(&mut child, "daemon-ably", "daemon_startup");
                        if !tasks.is_empty() {
                            initial_sidecar_log_tasks
                                .entry("daemon-ably".to_string())
                                .or_default()
                                .extend(tasks);
                        }
                        daemon_ably_ready = true;
                        initial_daemon_ably_process = Some(child);
                        info!(
                            runtime = "sidecar",
                            component = "sidecar.daemon-ably",
                            event_code = "daemon.presence.sidecar.started",
                            user_id_hash = %user_id_hash,
                            device_id_hash = %device_id_hash,
                            presence_channel = %presence_channel,
                            presence_event = DAEMON_PRESENCE_EVENT,
                            socket = %daemon_ably_socket_path.display(),
                            "Started daemon-ably sidecar for shared Ably transport"
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
                            "Failed to start daemon-ably sidecar; Falco/Nagato sidecars remain disabled"
                        );
                    }
                }
            }
            _ => warn!(
                "Authenticated session found, but user/device identifiers are missing; daemon-ably remains disabled"
            ),
        }
    } else {
        info!("No authenticated session at startup; skipping daemon-ably sidecar");
    }

    let mut initial_falco_process: Option<Child> = None;
    let mut initial_realtime_runtime_status_sync: Option<Arc<AblyRuntimeStatusSyncer>> = None;
    let initial_realtime_message_sync = if has_startup_auth_context && daemon_ably_ready {
        let falco_socket_path = paths.falco_socket_file();

        match local_device_id.as_deref() {
            Some(device_id) => {
                // Strict ownership: never adopt a pre-existing Falco socket.
                if falco_socket_path.exists() {
                    if let Err(err) = std::fs::remove_file(&falco_socket_path) {
                        warn!(
                            socket = %falco_socket_path.display(),
                            error = %err,
                            "Failed removing stale Falco socket before startup"
                        );
                    }
                }

                match start_falco_sidecar(
                    &paths,
                    device_id,
                    &config.log_level,
                    Duration::from_secs(5),
                    "daemon_startup",
                )
                .await
                {
                    Ok(mut child) => {
                        let tasks =
                            attach_sidecar_log_streams(&mut child, "falco", "daemon_startup");
                        if !tasks.is_empty() {
                            initial_sidecar_log_tasks
                                .entry("falco".to_string())
                                .or_default()
                                .extend(tasks);
                        }
                        initial_falco_process = Some(child);
                        match ensure_socket_connectable(&falco_socket_path).await {
                            Ok(()) => {
                                let armin_handle: toshinori::AblyArminHandle = armin.clone();
                                let syncer = Arc::new(AblyRealtimeSyncer::new(
                                    AblySyncConfig::default(),
                                    armin_handle,
                                    db_encryption_key_arc.clone(),
                                    falco_socket_path.clone(),
                                ));
                                let runtime_status_syncer =
                                    Arc::new(AblyRuntimeStatusSyncer::new(falco_socket_path));
                                toshinori.set_realtime_message_syncer(syncer.clone()).await;
                                toshinori
                                    .set_realtime_runtime_status_syncer(
                                        runtime_status_syncer.clone(),
                                    )
                                    .await;
                                syncer.start();
                                runtime_status_syncer.start();
                                initial_realtime_runtime_status_sync = Some(runtime_status_syncer);
                                info!(
                                    "Initialized Ably hot-path sync workers (conversation + runtime status)"
                                );
                                Some(syncer)
                            }
                            Err(err) => {
                                warn!(
                                    socket = %falco_socket_path.display(),
                                    error = %err,
                                    "Falco socket unavailable after startup; disabling Ably hot-path message sync"
                                );
                                None
                            }
                        }
                    }
                    Err(err) => {
                        warn!(
                            error = %err,
                            "Falco did not become ready; disabling Ably hot-path message sync"
                        );
                        None
                    }
                }
            }
            None => {
                warn!(
                    "Authenticated session found, but device ID is missing; disabling Ably hot-path message sync"
                );
                None
            }
        }
    } else {
        info!("Ably hot-path sync worker disabled at startup");
        None
    };

    // Connect Toshinori to Levi for message sync
    toshinori.set_message_syncer(message_sync.clone()).await;

    // Start Levi processing loop
    message_sync.start();

    // If startup validation recovered an authenticated session, initialize sync contexts.
    if let Some(sync) = startup_sync_context {
        let sync_context = SyncContext {
            access_token: sync.access_token,
            user_id: sync.user_id,
            device_id: sync.device_id,
        };
        toshinori.set_context(sync_context.clone()).await;
        message_sync.set_context(sync_context.clone()).await;
        if let Some(syncer) = &initial_realtime_message_sync {
            syncer.set_context(sync_context.clone()).await;
        }
        if let Some(syncer) = &initial_realtime_runtime_status_sync {
            syncer.set_context(sync_context.clone()).await;
        }
        info!("Initialized Supabase sync contexts from persisted auth session");
    }

    // Note: Armin was already initialized above with paths.database_file()
    // The old armin.db path is no longer used - all data is in daemon.db

    // Create shared state (Clone-able with internal Arc)
    let gyomei = Arc::new(Gyomei::with_defaults());
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
        toshinori,
        message_sync,
        realtime_message_sync: Arc::new(tokio::sync::RwLock::new(initial_realtime_message_sync)),
        realtime_runtime_status_sync: Arc::new(tokio::sync::RwLock::new(
            initial_realtime_runtime_status_sync,
        )),
        falco_process: Arc::new(Mutex::new(initial_falco_process)),
        nagato_process: Arc::new(Mutex::new(None)),
        daemon_ably_process: Arc::new(Mutex::new(initial_daemon_ably_process)),
        sidecar_log_tasks: Arc::new(Mutex::new(initial_sidecar_log_tasks)),
        itachi_idempotency: Arc::new(Mutex::new(IdempotencyStore::default())),
        nagato_shutdown_tx: Arc::new(Mutex::new(None)),
        nagato_server_task: Arc::new(Mutex::new(None)),
        sidecar_supervisor_shutdown_tx: Arc::new(Mutex::new(None)),
        sidecar_supervisor_task: Arc::new(Mutex::new(None)),
        sidecar_lifecycle_lock: Arc::new(tokio::sync::Mutex::new(())),
        ably_broker_nagato_token,
        ably_broker_falco_token,
        ably_broker_cache,
        armin,
        gyomei,
        billing_quota_cache: Arc::new(Mutex::new(Default::default())),
    };

    spawn_billing_quota_refresh_loop(state.clone());

    {
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let task = spawn_nagato_server(state.clone(), shutdown_rx);
        *state.nagato_shutdown_tx.lock().unwrap() = Some(shutdown_tx);
        *state.nagato_server_task.lock().unwrap() = Some(task);
    }

    if has_startup_auth_context && daemon_ably_ready {
        match local_device_id.as_deref() {
            Some(device_id) => match start_nagato_sidecar(
                state.paths.as_ref(),
                device_id,
                &state.config.log_level,
                Duration::from_secs(1),
                "daemon_startup",
            )
            .await
            {
                Ok(mut child) => {
                    let tasks =
                        attach_sidecar_log_streams(&mut child, "nagato", "daemon_startup");
                    register_sidecar_log_tasks(&state, "nagato", tasks);
                    *state.nagato_process.lock().unwrap() = Some(child);
                    info!("Started Nagato sidecar for remote command ingress");
                }
                Err(err) => warn!(
                    error = %err,
                    "Failed to start Nagato sidecar; remote command ingress disabled"
                ),
            },
            None => warn!(
                "Authenticated session found, but device ID is missing; disabling Nagato remote command ingress"
            ),
        }
    } else {
        info!("Nagato remote command ingress disabled at startup");
    }

    {
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let task = spawn_sidecar_supervisor(state.clone(), shutdown_rx);
        *state.sidecar_supervisor_shutdown_tx.lock().unwrap() = Some(shutdown_tx);
        *state.sidecar_supervisor_task.lock().unwrap() = Some(task);
    }

    // Load session secrets from Supabase into memory cache
    // This runs in the background to not block daemon startup
    let state_for_loading = state.clone();
    tokio::spawn(async move {
        match load_session_secrets_from_supabase(&state_for_loading).await {
            Ok(count) if count > 0 => info!("Loaded {} session secrets from Supabase", count),
            Ok(_) => debug!("No session secrets to load from Supabase"),
            Err(e) => warn!("Failed to load session secrets from Supabase: {}", e),
        }
    });

    // Reconcile local sessions with Supabase: ensure any session that has
    // pending messages to sync also exists in Supabase's agent_coding_sessions
    // table. Without this, Levi's message inserts fail RLS policy checks.
    {
        use armin::SessionReader;

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

            // Collect unique repository IDs to sync first (FK dependency)
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

                // Sync repository first if not already done (FK dependency)
                let repo_id = session.repository_id.as_str().to_string();
                if !synced_repos.contains(&repo_id) {
                    if let Err(e) = session_sync_ref.sync_repository(&repo_id).await {
                        warn!(session_id, repository_id = %repo_id, error = %e, "Failed to reconcile repository");
                        // Continue anyway — repo may already exist in Supabase
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

    let runtime_state = state.clone();

    // Register handlers
    register_handlers(&ipc_server, state).await;

    // Run server
    info!(
        socket = %paths.socket_file().display(),
        "IPC server starting"
    );

    let server_result = ipc_server.run().await;

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

    if let Some(runtime) = ably_broker_runtime.take() {
        let _ = runtime.shutdown_tx.send(());
        if let Err(err) = runtime.task.await {
            warn!(error = %err, "Ably broker task join failed");
        }
    }

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

    // Cleanup
    let _ = std::fs::remove_file(paths.pid_file());
    let _ = std::fs::remove_file(paths.socket_file());
    for sidecar_socket in paths.sidecar_socket_files() {
        let _ = std::fs::remove_file(sidecar_socket);
    }
    let _ = std::fs::remove_file(paths.ably_auth_socket_file());

    info!("Daemon stopped");

    server_result.map_err(|e| e.into())
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
