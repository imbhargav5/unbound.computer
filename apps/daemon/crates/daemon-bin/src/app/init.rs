//! Daemon initialization.

use crate::ably::start_ably_token_broker;
use crate::app::falco_sidecar::{ensure_socket_connectable, start_falco_sidecar, terminate_child};
use crate::app::nagato_server::spawn_nagato_server;
use crate::app::nagato_sidecar::start_nagato_sidecar;
use crate::app::DaemonState;
use crate::armin_adapter::create_daemon_armin;
use crate::ipc::register_handlers;
use crate::itachi::idempotency::IdempotencyStore;
use crate::utils::{load_session_secrets_from_supabase, SessionSecretCache};
use daemon_config_and_utils::{Config, Paths};
use daemon_database::AsyncDatabase;
use daemon_ipc::IpcServer;
use daemon_storage::create_secrets_manager;
use gyomei::Gyomei;
use levi::SessionSyncService;
use levi::{Levi, LeviConfig};
use std::collections::HashMap;
use std::process::Child;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use toshinori::{AblyRealtimeSyncer, AblySyncConfig, SyncContext, ToshinoriSink};
use tracing::{debug, info, warn};
use ymir::{DaemonAuthRuntime, SessionManager, SupabaseClient};

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
        Ok(true) => info!("Existing session validated successfully"),
        Ok(false) => info!("No existing session to validate"),
        Err(e) => warn!(
            "Session validation failed, user will need to re-authenticate: {}",
            e
        ),
    }

    let mut ably_broker_runtime = Some(
        start_ably_token_broker(paths.ably_auth_socket_file(), auth_runtime.clone())
            .await
            .map_err(|err| format!("Failed to start Ably token broker: {}", err))?,
    );

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

    let mut initial_falco_process: Option<Child> = None;
    let initial_realtime_message_sync = if let Some(ably_api_key) = config.ably_api_key.as_deref() {
        let falco_socket_path = paths.falco_socket_file();

        if !falco_socket_path.exists() {
            match local_device_id.as_deref() {
                Some(device_id) => match start_falco_sidecar(
                    &paths,
                    device_id,
                    ably_api_key,
                    &config.log_level,
                    Duration::from_secs(5),
                    "daemon_startup",
                )
                .await
                {
                    Ok(child) => {
                        info!(
                            socket = %falco_socket_path.display(),
                            "Started Falco sidecar for Ably hot-path sync"
                        );
                        initial_falco_process = Some(child);
                    }
                    Err(err) => warn!(
                        error = %err,
                        "Falco did not become ready; disabling Ably hot-path message sync"
                    ),
                },
                None => warn!(
                    "Ably API key configured but device ID is missing; disabling Ably hot-path message sync"
                ),
            }
        } else {
            info!(
                socket = %falco_socket_path.display(),
                "Using existing Falco socket for Ably hot-path sync"
            );
        }

        // If socket exists but isn't connectable, clean up and re-spawn.
        if falco_socket_path.exists() {
            if let Err(err) = ensure_socket_connectable(&falco_socket_path).await {
                warn!(
                    socket = %falco_socket_path.display(),
                    error = %err,
                    "Falco socket exists but is not connectable; removing stale socket and re-spawning"
                );
                if let Err(rm_err) = std::fs::remove_file(&falco_socket_path) {
                    warn!(
                        socket = %falco_socket_path.display(),
                        error = %rm_err,
                        "Failed to remove stale Falco socket; disabling Ably hot-path message sync"
                    );
                } else if let Some(device_id) = local_device_id.as_deref() {
                    match start_falco_sidecar(
                        &paths,
                        device_id,
                        ably_api_key,
                        &config.log_level,
                        Duration::from_secs(5),
                        "stale_socket_recovery",
                    )
                    .await
                    {
                        Ok(child) => {
                            info!(
                                socket = %falco_socket_path.display(),
                                "Re-started Falco sidecar after stale socket cleanup"
                            );
                            initial_falco_process = Some(child);
                        }
                        Err(spawn_err) => warn!(
                            error = %spawn_err,
                            "Failed to re-start Falco after stale socket cleanup; disabling Ably hot-path message sync"
                        ),
                    }
                }
            }
        }

        if falco_socket_path.exists() {
            match ensure_socket_connectable(&falco_socket_path).await {
                Ok(()) => {
                    let armin_handle: toshinori::AblyArminHandle = armin.clone();
                    let syncer = Arc::new(AblyRealtimeSyncer::new(
                        AblySyncConfig::default(),
                        armin_handle,
                        db_encryption_key_arc.clone(),
                        falco_socket_path,
                    ));
                    toshinori.set_realtime_message_syncer(syncer.clone()).await;
                    syncer.start();
                    info!("Initialized Ably hot-path message sync worker");
                    Some(syncer)
                }
                Err(err) => {
                    warn!(
                        socket = %falco_socket_path.display(),
                        error = %err,
                        "Falco socket not connectable after recovery attempt; disabling Ably hot-path message sync"
                    );
                    None
                }
            }
        } else {
            None
        }
    } else {
        info!("Ably API key not configured, skipping Ably hot-path sync worker");
        None
    };

    // Connect Toshinori to Levi for message sync
    toshinori.set_message_syncer(message_sync.clone()).await;

    // Start Levi processing loop
    message_sync.start();

    // If startup validation recovered an authenticated session, initialize sync contexts.
    if let Ok(Some(sync)) = auth_runtime.current_sync_context() {
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
        falco_process: Arc::new(Mutex::new(initial_falco_process)),
        nagato_process: Arc::new(Mutex::new(None)),
        itachi_idempotency: Arc::new(Mutex::new(IdempotencyStore::default())),
        nagato_shutdown_tx: Arc::new(Mutex::new(None)),
        nagato_server_task: Arc::new(Mutex::new(None)),
        armin,
        gyomei,
    };

    {
        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let task = spawn_nagato_server(state.clone(), shutdown_rx);
        *state.nagato_shutdown_tx.lock().unwrap() = Some(shutdown_tx);
        *state.nagato_server_task.lock().unwrap() = Some(task);
    }

    if let Some(ably_api_key) = state.config.ably_api_key.as_deref() {
        match local_device_id.as_deref() {
            Some(device_id) => match start_nagato_sidecar(
                state.paths.as_ref(),
                device_id,
                ably_api_key,
                &state.config.log_level,
                Duration::from_secs(1),
                "daemon_startup",
            )
            .await
            {
                Ok(child) => {
                    *state.nagato_process.lock().unwrap() = Some(child);
                    info!("Started Nagato sidecar for remote command ingress");
                }
                Err(err) => warn!(
                    error = %err,
                    "Failed to start Nagato sidecar; remote command ingress disabled"
                ),
            },
            None => warn!(
                "Ably API key configured but device ID is missing; disabling Nagato remote command ingress"
            ),
        }
    } else {
        info!("Ably API key not configured, skipping Nagato remote command ingress");
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

    // Cleanup
    let _ = std::fs::remove_file(paths.pid_file());
    let _ = std::fs::remove_file(paths.socket_file());

    info!("Daemon stopped");

    server_result.map_err(|e| e.into())
}
