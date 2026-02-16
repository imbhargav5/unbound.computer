//! Unbound CLI - Command-line interface for the Unbound daemon.

mod commands;
mod output;
mod tui;

use clap::{Parser, Subcommand};
use tracing::{debug, info};

/// Unbound CLI - Control the Unbound daemon and manage coding sessions.
#[derive(Parser)]
#[command(name = "unbound")]
#[command(about = "Unbound CLI for authentication and session management")]
#[command(version)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Launch the interactive terminal UI
    #[arg(long)]
    ui: bool,

    /// Use terminal-adaptive colors instead of Unbound theme (only with --ui)
    #[arg(long)]
    terminal_colors: bool,

    /// Output format (text or json)
    #[arg(short, long, default_value = "text", global = true)]
    format: output::OutputFormat,

    /// Log level (trace, debug, info, warn, error)
    #[arg(long, default_value = "warn", global = true)]
    log_level: String,
}

#[derive(Subcommand)]
enum Commands {
    /// Login with email and password
    Login,

    /// Logout and clear session
    Logout,

    /// Check authentication status
    Status,

    /// Manage the daemon
    Daemon {
        #[command(subcommand)]
        command: DaemonCommands,
    },

    /// Manage coding sessions
    Sessions {
        #[command(subcommand)]
        command: SessionCommands,
    },

    /// Manage repositories
    Repos {
        #[command(subcommand)]
        command: RepoCommands,
    },
}

#[derive(Subcommand)]
enum DaemonCommands {
    /// Start the daemon
    Start {
        /// Run in foreground
        #[arg(short, long)]
        foreground: bool,
    },
    /// Stop the daemon
    Stop,
    /// Check daemon status
    Status,
    /// View daemon logs
    Logs {
        /// Number of lines to show
        #[arg(short, long, default_value = "50")]
        lines: usize,
        /// Follow log output
        #[arg(short, long)]
        follow: bool,
    },
}

#[derive(Subcommand)]
enum SessionCommands {
    /// List sessions
    List {
        /// Filter by repository ID
        #[arg(short, long)]
        repository: Option<String>,
    },
    /// Show session details
    Show {
        /// Session ID
        id: String,
    },
    /// Create a new session
    Create {
        /// Repository ID
        #[arg(short, long)]
        repository: String,
        /// Session title
        #[arg(short, long)]
        title: Option<String>,
    },
    /// Delete a session
    Delete {
        /// Session ID
        id: String,
    },
    /// List messages in a session
    Messages {
        /// Session ID
        id: String,
    },
}

#[derive(Subcommand)]
enum RepoCommands {
    /// List repositories
    List,
    /// Add a repository
    Add {
        /// Path to repository
        path: String,
    },
    /// Remove a repository
    Remove {
        /// Repository ID
        id: String,
    },
}

/// Ensure user is authenticated before starting TUI.
/// If not logged in, prompts for email/password.
async fn ensure_authenticated() -> anyhow::Result<()> {
    use std::io::{self, Write};

    // Check if daemon is running - never auto-start, daemon is a singleton
    let client = commands::get_daemon_client().await.map_err(|_| {
        anyhow::anyhow!("Daemon is not running. Start it separately with 'unbound daemon start'")
    })?;

    // Check auth status
    let response = client.call_method(daemon_ipc::Method::AuthStatus).await?;

    if let Some(result) = &response.result {
        let logged_in = result
            .get("logged_in")
            .or_else(|| result.get("authenticated"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);

        if logged_in {
            // Already authenticated
            return Ok(());
        }
    }

    // Not authenticated - prompt for email/password
    println!();
    println!("Authentication required.");
    println!();

    print!("Email: ");
    io::stdout().flush()?;
    let mut email = String::new();
    io::stdin().read_line(&mut email)?;
    let email = email.trim().to_string();

    if email.is_empty() {
        anyhow::bail!("Email is required");
    }

    // Read password without echo
    let password = rpassword::prompt_password("Password: ")?;

    if password.is_empty() {
        anyhow::bail!("Password is required");
    }

    println!();
    println!("Logging in...");

    let params = serde_json::json!({
        "email": email,
        "password": password,
    });

    let response = client
        .call_method_with_params(daemon_ipc::Method::AuthLogin, params)
        .await?;

    if response.is_success() {
        if let Some(result) = &response.result {
            let email_display = result
                .get("email")
                .and_then(|v| v.as_str())
                .or_else(|| result.get("user_id").and_then(|v| v.as_str()))
                .unwrap_or("user");
            println!("Logged in as {}", email_display);
            println!();
        }
        Ok(())
    } else if let Some(error) = &response.error {
        anyhow::bail!("Login failed: {}", error.message);
    } else {
        anyhow::bail!("Login failed");
    }
}

/// Find the git repository root from the current directory.
/// Returns None if not inside a git repository.
fn find_git_root() -> Option<std::path::PathBuf> {
    let current_dir = std::env::current_dir().ok()?;
    let mut dir = current_dir.as_path();

    loop {
        if dir.join(".git").exists() {
            return Some(dir.to_path_buf());
        }
        dir = dir.parent()?;
    }
}

/// Ask user for confirmation.
fn confirm(prompt: &str) -> bool {
    use std::io::{self, Write};

    print!("{} [y/N] ", prompt);
    io::stdout().flush().ok();

    let mut input = String::new();
    if io::stdin().read_line(&mut input).is_err() {
        return false;
    }

    matches!(input.trim().to_lowercase().as_str(), "y" | "yes")
}

/// Ensure the current git repository is added to the daemon.
/// Returns the repository ID if successful.
async fn ensure_repo_added() -> Option<String> {
    let git_root = find_git_root()?;
    let path_str = git_root.to_string_lossy().to_string();

    debug!(path = %path_str, "Found git repository");

    // Try to connect to daemon
    let client = match commands::get_daemon_client().await {
        Ok(client) => client,
        Err(e) => {
            debug!("Daemon not running: {}", e);
            return None;
        }
    };

    // Check if repo already exists
    if let Ok(response) = client.call_method(daemon_ipc::Method::RepositoryList).await {
        if let Some(result) = &response.result {
            if let Some(repos) = result.get("repositories").and_then(|v| v.as_array()) {
                for repo in repos {
                    if let Some(repo_path) = repo.get("path").and_then(|v| v.as_str()) {
                        if repo_path == path_str {
                            let repo_id = repo.get("id").and_then(|v| v.as_str()).map(String::from);
                            debug!(id = ?repo_id, "Repository already exists");
                            return repo_id;
                        }
                    }
                }
            }
        }
    }

    // Repository not found - ask for confirmation
    let name = git_root
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unnamed")
        .to_string();

    println!("Git repository detected: {}", name);
    println!("Path: {}", path_str);

    if !confirm("Add this repository to Unbound?") {
        debug!("User declined to add repository");
        return None;
    }

    // Add the repository
    let params = serde_json::json!({
        "path": path_str,
        "name": name,
        "is_git_repository": true,
    });

    match client
        .call_method_with_params(daemon_ipc::Method::RepositoryAdd, params)
        .await
    {
        Ok(response) => {
            if let Some(result) = &response.result {
                let repo_id = result.get("id").and_then(|v| v.as_str()).map(String::from);
                println!("Repository added successfully.");
                info!(id = ?repo_id, name = %name, "Repository added");
                return repo_id;
            }
        }
        Err(e) => {
            debug!("Failed to add repository: {}", e);
        }
    }

    None
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    // Initialize logging via observability crate
    observability::init_with_config(observability::LogConfig {
        service_name: "cli".into(),
        default_level: cli.log_level.clone(),
        also_stderr: false, // CLI doesn't need stderr output by default
        ..Default::default()
    });

    // Handle --ui flag or explicit tui command
    let result = if cli.ui && cli.command.is_none() {
        // --ui flag: launch TUI
        if let Err(e) = ensure_authenticated().await {
            eprintln!("Error: {}", e);
            return;
        }
        let _repo_id = ensure_repo_added().await;
        let theme_mode = if cli.terminal_colors {
            tui::ThemeMode::Terminal
        } else {
            tui::ThemeMode::Unbound
        };
        tui::run(theme_mode).await
    } else if let Some(command) = cli.command {
        match command {
            Commands::Login => commands::login(&cli.format).await,
            Commands::Logout => commands::logout(&cli.format).await,
            Commands::Status => commands::status(&cli.format).await,
            Commands::Daemon { command } => match command {
                DaemonCommands::Start { foreground } => commands::daemon_start(foreground).await,
                DaemonCommands::Stop => commands::daemon_stop(&cli.format).await,
                DaemonCommands::Status => commands::daemon_status(&cli.format).await,
                DaemonCommands::Logs { lines, follow } => {
                    commands::daemon_logs(lines, follow).await
                }
            },
            Commands::Sessions { command } => match command {
                SessionCommands::List { repository } => {
                    commands::sessions_list(repository.as_deref(), &cli.format).await
                }
                SessionCommands::Show { id } => commands::sessions_show(&id, &cli.format).await,
                SessionCommands::Create { repository, title } => {
                    commands::sessions_create(&repository, title.as_deref(), &cli.format).await
                }
                SessionCommands::Delete { id } => commands::sessions_delete(&id, &cli.format).await,
                SessionCommands::Messages { id } => {
                    commands::sessions_messages(&id, &cli.format).await
                }
            },
            Commands::Repos { command } => match command {
                RepoCommands::List => commands::repos_list(&cli.format).await,
                RepoCommands::Add { path } => commands::repos_add(&path, &cli.format).await,
                RepoCommands::Remove { id } => commands::repos_remove(&id, &cli.format).await,
            },
        }
    } else {
        // Default: no command, no --ui flag
        // Just ensure daemon is running, check auth, and add repo
        if let Err(e) = ensure_authenticated().await {
            eprintln!("Error: {}", e);
            return;
        }
        let repo_id = ensure_repo_added().await;
        if let Some(id) = repo_id {
            println!("Repository ready. Use 'unbound --ui' to launch the terminal UI.");
            debug!(repo_id = %id, "Repository ready");
        } else if find_git_root().is_none() {
            println!("Not in a git repository. Use 'unbound --ui' to launch the terminal UI.");
        }
        Ok(())
    };

    if let Err(e) = result {
        eprintln!("Error: {}", e);
        std::process::exit(1);
    }
}
