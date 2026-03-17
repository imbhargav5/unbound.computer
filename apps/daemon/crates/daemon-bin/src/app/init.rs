//! Daemon initialization.

use crate::app::{AgentRunCoordinator, DaemonState, StartupStatusWriter};
use crate::armin_adapter::create_daemon_armin;
use crate::ipc::register_handlers;
use crate::utils::SessionSecretCache;
use daemon_config_and_utils::{force_flush, shutdown, Config, Paths};
use daemon_database::AsyncDatabase;
use daemon_ipc::IpcServer;
use daemon_storage::{create_secrets_manager, SecretsManager};
use safe_file_ops::SafeFileOps;
#[cfg(unix)]
use signal_hook::consts::signal::{SIGINT, SIGTERM};
#[cfg(unix)]
use signal_hook::iterator::Signals;
use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, Mutex};
use tokio::task::JoinHandle;
use tokio::time::{sleep, Duration, Instant};
use tracing::info;

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

    info!("Starting local-only Unbound daemon");

    startup_status.update("critical_bootstrap", "Ensuring runtime directories exist");
    paths.ensure_dirs()?;

    startup_status.update("critical_bootstrap", "Writing daemon PID file");
    let pid = std::process::id();
    std::fs::write(paths.pid_file(), pid.to_string())?;
    info!(pid = pid, "Daemon started");

    startup_status.update("critical_bootstrap", "Initializing IPC server");
    let ipc_server = Arc::new(IpcServer::new(&paths.socket_file().to_string_lossy()));

    startup_status.update("critical_bootstrap", "Initializing Armin session engine");
    let armin = create_daemon_armin(&paths.database_file(), ipc_server.subscriptions().clone())
        .map_err(|e| format!("Failed to initialize Armin: {}", e))?;
    info!(
        path = %paths.database_file().display(),
        "Armin session engine initialized"
    );

    startup_status.update("critical_bootstrap", "Opening async database");
    let db = AsyncDatabase::open(&paths.database_file())
        .await
        .map_err(|e| format!("Failed to open async database: {}", e))?;
    info!("Async database initialized");

    startup_status.update("critical_bootstrap", "Initializing secure storage");
    let secrets = create_secrets_manager()?;
    let device_id = ensure_local_device_id(&secrets)?;
    let device_private_key = ensure_local_device_private_key(&secrets)?;
    let db_encryption_key = secrets
        .get_database_encryption_key()?
        .ok_or_else(|| "Database encryption key is unavailable".to_string())?;
    info!(device_id = %device_id, "Local device identity ready");

    let config = Arc::new(config);
    let shared_paths = Arc::new(paths.clone());
    let claude_processes = Arc::new(Mutex::new(HashMap::new()));
    let device_id_state = Arc::new(Mutex::new(Some(device_id)));
    let agent_run_coordinator = Arc::new(AgentRunCoordinator::new(
        db.clone(),
        shared_paths.clone(),
        armin.clone(),
        ipc_server.subscriptions().clone(),
        claude_processes.clone(),
        device_id_state.clone(),
    ));

    let state = DaemonState {
        config,
        paths: shared_paths,
        db,
        secrets: Arc::new(Mutex::new(secrets)),
        claude_processes,
        agent_run_coordinator,
        terminal_processes: Arc::new(Mutex::new(HashMap::new())),
        db_encryption_key: Arc::new(Mutex::new(Some(db_encryption_key))),
        subscriptions: ipc_server.subscriptions().clone(),
        session_secret_cache: SessionSecretCache::new(),
        device_id: device_id_state,
        device_private_key: Arc::new(Mutex::new(Some(device_private_key))),
        armin,
        safe_file_ops: Arc::new(SafeFileOps::with_defaults()),
    };

    state.agent_run_coordinator.clone().spawn_background();

    register_handlers(&ipc_server, state.clone()).await;

    startup_status.update("critical_bootstrap", "Starting IPC server");
    let socket_path = paths.socket_file();
    let ipc_server_task = ipc_server.clone();
    let mut ipc_task = tokio::spawn(async move { ipc_server_task.run().await });
    spawn_shutdown_signal_task(ipc_server.clone())?;
    if let Err(error) =
        wait_for_ipc_socket_ready(&socket_path, &mut ipc_task, &startup_status).await
    {
        startup_status.update("critical_bootstrap_failed", &error.to_string());
        remove_runtime_files(&paths);
        force_flush();
        shutdown();
        return Err(error);
    }

    startup_status.update("ready", "Daemon IPC socket is listening");

    let server_result = match ipc_task.await {
        Ok(result) => result.map_err(|err| -> Box<dyn std::error::Error> { err.into() }),
        Err(err) => Err(format!("IPC server task join failed: {err}").into()),
    };

    startup_status.update("stopped", "Daemon shutdown complete");
    info!("Daemon stopped");
    force_flush();
    shutdown();
    remove_runtime_files(&paths);

    server_result
}

fn ensure_local_device_id(secrets: &SecretsManager) -> Result<String, Box<dyn std::error::Error>> {
    if let Some(device_id) = secrets.get_device_id()? {
        return Ok(device_id);
    }

    let device_id = uuid::Uuid::new_v4().to_string();
    secrets.set_device_id(&device_id)?;
    Ok(device_id)
}

fn ensure_local_device_private_key(
    secrets: &SecretsManager,
) -> Result<[u8; 32], Box<dyn std::error::Error>> {
    let key = secrets.ensure_device_private_key()?;
    let key: [u8; 32] = key
        .try_into()
        .map_err(|_| "Device private key must be 32 bytes")?;
    Ok(key)
}

fn spawn_shutdown_signal_task(ipc_server: Arc<IpcServer>) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        let mut signals = Signals::new([SIGINT, SIGTERM])?;
        std::thread::spawn(move || {
            if let Some(signal) = signals.forever().next() {
                let signal_name = match signal {
                    SIGINT => "SIGINT",
                    SIGTERM => "SIGTERM",
                    _ => "unknown",
                };
                info!(signal = signal_name, "Shutdown signal received");
                ipc_server.shutdown();
            }
        });
        Ok(())
    }

    #[cfg(not(unix))]
    {
        tokio::spawn(async move {
            match tokio::signal::ctrl_c().await {
                Ok(()) => {
                    info!(signal = "SIGINT", "Shutdown signal received");
                    ipc_server.shutdown();
                }
                Err(err) => {
                    tracing::warn!(error = %err, "Failed to listen for shutdown signal");
                }
            }
        });
        Ok(())
    }
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

fn remove_runtime_files(paths: &Paths) {
    let _ = std::fs::remove_file(paths.pid_file());
    let _ = std::fs::remove_file(paths.socket_file());
}
