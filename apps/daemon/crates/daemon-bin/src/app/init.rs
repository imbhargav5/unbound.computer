//! Daemon initialization.

use crate::app::DaemonState;
use crate::armin_adapter::create_daemon_armin;
use crate::ipc::register_handlers;
use crate::outbox::SessionSyncService;
use crate::utils::{load_session_secrets_from_supabase, SessionSecretCache};
use daemon_auth::{SessionManager, SupabaseClient};
use daemon_core::{Config, Paths};
use daemon_database::{DatabasePool, PoolConfig};
use daemon_ipc::IpcServer;
use daemon_storage::create_secrets_manager;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tracing::{debug, info, warn};

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
        if client
            .call_method(daemon_ipc::Method::Health)
            .await
            .is_ok()
        {
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

    // Initialize database with connection pool
    let db = DatabasePool::open(&paths.database_file(), PoolConfig::default())?;
    info!(
        path = %paths.database_file().display(),
        "Database pool initialized"
    );

    // Initialize secure storage
    let secrets = create_secrets_manager()?;
    info!("Secure storage initialized");

    // Validate existing session on startup
    // If the user is already signed in, verify the session is still valid
    // and refresh if needed. If refresh fails, clean up the session.
    {
        let session_manager = SessionManager::new(
            create_secrets_manager()?,
            &config.supabase_url,
            &config.supabase_publishable_key,
        );
        match session_manager.validate_session_on_startup().await {
            Ok(true) => info!("Existing session validated successfully"),
            Ok(false) => info!("No existing session to validate"),
            Err(e) => warn!(
                "Session validation failed, user will need to re-authenticate: {}",
                e
            ),
        }
    }

    // Get and cache the database encryption key at startup
    // This avoids repeated keychain access on every message operation
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

    // Get device ID and private key for session secret distribution
    let device_id = secrets.get_device_id().ok().flatten();
    let device_private_key = secrets
        .get_device_private_key()
        .ok()
        .flatten()
        .and_then(|k| k.try_into().ok());

    if device_id.is_some() && device_private_key.is_some() {
        info!("Device identity loaded for multi-device session secret distribution");
    }

    // Create Supabase client for device management and secret distribution
    let supabase_client = Arc::new(SupabaseClient::new(
        &config.supabase_url,
        &config.supabase_publishable_key,
    ));
    info!("Supabase client initialized");

    // Start IPC server (create first to get subscription manager)
    let ipc_server = IpcServer::new(&paths.socket_file().to_string_lossy());

    // Create shared Arc values for reuse
    let db_arc = Arc::new(db);
    let secrets_arc = Arc::new(Mutex::new(secrets));
    let device_id_arc = Arc::new(Mutex::new(device_id));
    let device_private_key_arc = Arc::new(Mutex::new(device_private_key));

    // Create session secret cache (fast in-memory lookup)
    let session_secret_cache = SessionSecretCache::new();

    // Create session sync service (shares cache via inner Arc)
    let session_sync = Arc::new(SessionSyncService::new(
        supabase_client.clone(),
        db_arc.clone(),
        secrets_arc.clone(),
        device_id_arc.clone(),
        device_private_key_arc.clone(),
        session_secret_cache.inner(),
    ));

    // Initialize Armin session engine for fast in-memory reads
    // Armin uses its own SQLite database separate from the main daemon database
    let armin_db_path = paths.base_dir().join("armin.db");
    let armin = create_daemon_armin(&armin_db_path, ipc_server.subscriptions().clone())
        .map_err(|e| format!("Failed to initialize Armin: {}", e))?;

    // Create shared state (Clone-able with internal Arc)
    let state = DaemonState {
        config: Arc::new(config),
        paths: Arc::new(paths.clone()),
        db: db_arc,
        secrets: secrets_arc,
        claude_processes: Arc::new(Mutex::new(HashMap::new())),
        terminal_processes: Arc::new(Mutex::new(HashMap::new())),
        db_encryption_key: Arc::new(Mutex::new(db_encryption_key)),
        subscriptions: ipc_server.subscriptions().clone(),
        session_secret_cache,
        supabase_client,
        device_id: device_id_arc,
        device_private_key: device_private_key_arc,
        session_sync,
        stream_producers: Arc::new(Mutex::new(HashMap::new())),
        armin,
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
