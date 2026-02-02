//! Falco binary entry point.
//!
//! Usage: falco [--device-id <id>]
//!
//! If --device-id is not provided, Falco will attempt to read it from
//! the system keychain.

use clap::Parser;
use falco::{Courier, FalcoConfig, FalcoResult};
use tracing::{error, info};

/// Falco: Stateless courier for encrypted remote commands.
#[derive(Parser, Debug)]
#[command(name = "falco")]
#[command(about = "Stateless, crash-safe courier for encrypted remote commands")]
struct Args {
    /// Device ID for the Redis stream key.
    /// If not provided, reads from system keychain.
    #[arg(long)]
    device_id: Option<String>,

    /// Redis connection URL.
    #[arg(long, env = "REDIS_URL", default_value = "redis://127.0.0.1:6379")]
    redis_url: String,

    /// Path to the daemon socket.
    #[arg(long, env = "FALCO_SOCKET")]
    socket: Option<String>,

    /// Daemon response timeout in seconds.
    #[arg(long, env = "FALCO_TIMEOUT_SECS", default_value = "15")]
    timeout_secs: u64,

    /// Log level (trace, debug, info, warn, error)
    #[arg(long, default_value = "info")]
    log_level: String,
}

fn get_device_id(args: &Args) -> FalcoResult<String> {
    if let Some(ref device_id) = args.device_id {
        return Ok(device_id.clone());
    }

    // Try to read from keychain
    let secrets = daemon_storage::create_secrets_manager()?;
    let device_id = secrets.get_device_id()?.ok_or_else(|| {
        falco::FalcoError::Config(
            "No device ID provided and none found in keychain. \
             Use --device-id or ensure the device is registered."
                .to_string(),
        )
    })?;

    Ok(device_id)
}

#[tokio::main]
async fn main() -> FalcoResult<()> {
    let args = Args::parse();

    // Initialize logging via observability crate
    observability::init_with_config(observability::LogConfig {
        service_name: "falco".into(),
        default_level: args.log_level.clone(),
        also_stderr: true,
        ..Default::default()
    });

    info!("Falco starting...");

    // Get device ID
    let device_id = get_device_id(&args)?;
    info!(device_id = %device_id, "Using device ID");

    // Build config
    let mut config = FalcoConfig::new(device_id)?;

    // Override with CLI args if provided
    config.redis_url = args.redis_url;
    config.daemon_timeout = std::time::Duration::from_secs(args.timeout_secs);

    if let Some(socket) = args.socket {
        config.socket_path = std::path::PathBuf::from(socket);
    }

    info!(
        redis_url = %config.redis_url,
        socket = %config.socket_path.display(),
        timeout_secs = config.daemon_timeout.as_secs(),
        stream = %config.stream_key(),
        consumer = %config.consumer_name,
        "Configuration loaded"
    );

    // Create and run the courier
    let mut courier = Courier::new(config).await?;

    // Install signal handlers for graceful shutdown
    let ctrl_c = tokio::signal::ctrl_c();

    tokio::select! {
        result = courier.run() => {
            if let Err(e) = result {
                error!(error = %e, "Courier exited with error");
                return Err(e);
            }
        }
        _ = ctrl_c => {
            info!("Received shutdown signal, exiting...");
        }
    }

    Ok(())
}
