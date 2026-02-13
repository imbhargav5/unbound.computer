//! Unbound Daemon - Background service for authentication, database, and relay communication.

mod ably;
mod app;
mod armin_adapter;
mod auth;
mod ipc;
mod itachi;
mod machines;
mod types;
mod utils;

use clap::{Parser, Subcommand};
use daemon_config_and_utils::{init_logging, Config, Paths};

/// Unbound daemon command-line interface.
#[derive(Parser)]
#[command(name = "unbound-daemon")]
#[command(about = "Unbound daemon for authentication and relay communication")]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Log level (trace, debug, info, warn, error)
    #[arg(short, long, default_value = "info", global = true)]
    log_level: String,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the daemon
    Start {
        /// Run in foreground (don't daemonize)
        #[arg(short, long)]
        foreground: bool,
    },
    /// Stop the daemon
    Stop,
    /// Check daemon status
    Status,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();

    // Initialize logging
    init_logging(&cli.log_level);

    // Load configuration
    let paths = Paths::new()?;
    let config = Config::load(&paths)?;

    match cli.command {
        Some(Commands::Start { foreground }) => {
            app::run_daemon(config, paths, foreground).await?;
        }
        None => {
            // Default to start in foreground if no command given
            app::run_daemon(config, paths, true).await?;
        }
        Some(Commands::Stop) => {
            app::stop_daemon(&paths).await?;
        }
        Some(Commands::Status) => {
            app::check_status(&paths).await?;
        }
    }

    Ok(())
}
