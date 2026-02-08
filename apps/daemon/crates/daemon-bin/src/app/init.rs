//! Daemon initialization.

use crate::app::DaemonState;
use crate::armin_adapter::create_daemon_armin;
use crate::ipc::register_handlers;
use crate::utils::{load_session_secrets_from_supabase, SessionSecretCache};
use daemon_config_and_utils::{Config, Paths};
use daemon_database::AsyncDatabase;
use daemon_ipc::IpcServer;
use daemon_storage::create_secrets_manager;
use gyomei::Gyomei;
use levi::SessionSyncService;
use levi::{Levi, LeviConfig};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use toshinori::{SyncContext, ToshinoriSink};
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
        relay_url = %config.relay.url,
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
        message_sync.set_context(sync_context).await;
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
        armin,
        gyomei,
    };

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

    // Register handlers
    register_handlers(&ipc_server, state).await;

    // Run server
    info!(
        socket = %paths.socket_file().display(),
        "IPC server starting"
    );

    let server_result = ipc_server.run().await;

    // Cleanup
    let _ = std::fs::remove_file(paths.pid_file());
    let _ = std::fs::remove_file(paths.socket_file());

    info!("Daemon stopped");

    server_result.map_err(|e| e.into())
}
