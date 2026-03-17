//! Unbound Daemon - Background service for authentication, database, and relay communication.

mod app;
mod armin_adapter;
mod ipc;
mod machines;
mod observability;
mod types;
mod utils;

use std::path::PathBuf;

use clap::{Args, Parser, Subcommand};
use daemon_config_and_utils::{init_logging, shutdown, Config, Paths};
use daemon_ipc::{IpcClient, Method};
use serde_json::{Map, Value};

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

    /// Base directory for runtime files (socket, logs, config). Defaults to ~/.unbound
    #[arg(long, global = true)]
    base_dir: Option<PathBuf>,
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
    /// Invoke board mutations against the running daemon
    Board {
        #[command(subcommand)]
        command: BoardCommands,
    },
}

#[derive(Subcommand)]
enum BoardCommands {
    /// Submit a governed hire request for a non-CEO agent
    HireAgent(HireAgentArgs),
    /// List board issues
    IssueList(IssueListArgs),
    /// Create a board issue
    IssueCreate(IssueCreateArgs),
    /// Get a board issue
    IssueGet(IssueGetArgs),
    /// Update a board issue
    IssueUpdate(IssueUpdateArgs),
    /// List board issue comments
    IssueCommentList(IssueCommentListArgs),
    /// Add a board issue comment
    IssueCommentAdd(IssueCommentAddArgs),
    /// List board issue attachments
    IssueAttachmentList(IssueAttachmentListArgs),
    /// Prepare the issue worktree and session
    IssueCheckout(IssueCheckoutArgs),
}

#[derive(Args)]
struct HireAgentArgs {
    #[arg(long)]
    company_id: String,
    #[arg(long)]
    name: String,
    #[arg(long)]
    role: Option<String>,
    #[arg(long)]
    title: Option<String>,
    #[arg(long)]
    icon: Option<String>,
    #[arg(long)]
    reports_to: Option<String>,
    #[arg(long)]
    capabilities: Option<String>,
    #[arg(long)]
    adapter_type: Option<String>,
    #[arg(long)]
    budget_monthly_cents: Option<i64>,
    #[arg(long)]
    requested_by_agent_id: Option<String>,
    #[arg(long)]
    requested_by_user_id: Option<String>,
    #[arg(long)]
    requested_by_run_id: Option<String>,
    #[arg(long = "source-issue-id")]
    source_issue_ids: Vec<String>,
    #[arg(long)]
    adapter_config_json: Option<String>,
    #[arg(long)]
    adapter_config_file: Option<PathBuf>,
    #[arg(long)]
    runtime_config_json: Option<String>,
    #[arg(long)]
    runtime_config_file: Option<PathBuf>,
    #[arg(long)]
    permissions_json: Option<String>,
    #[arg(long)]
    permissions_file: Option<PathBuf>,
    #[arg(long)]
    metadata_json: Option<String>,
    #[arg(long)]
    metadata_file: Option<PathBuf>,
}

#[derive(Args)]
struct IssueListArgs {
    #[arg(long)]
    company_id: String,
    #[arg(long)]
    project_id: Option<String>,
    #[arg(long)]
    parent_id: Option<String>,
    #[arg(long)]
    assignee_agent_id: Option<String>,
    #[arg(long)]
    include_hidden: bool,
}

#[derive(Args)]
struct IssueCreateArgs {
    #[arg(long)]
    company_id: String,
    #[arg(long)]
    title: String,
    #[arg(long)]
    description: Option<String>,
    #[arg(long)]
    description_file: Option<PathBuf>,
    #[arg(long)]
    status: Option<String>,
    #[arg(long)]
    priority: Option<String>,
    #[arg(long)]
    project_id: Option<String>,
    #[arg(long)]
    goal_id: Option<String>,
    #[arg(long)]
    parent_id: Option<String>,
    #[arg(long)]
    assignee_agent_id: Option<String>,
    #[arg(long)]
    assignee_user_id: Option<String>,
    #[arg(long)]
    created_by_agent_id: Option<String>,
    #[arg(long)]
    created_by_user_id: Option<String>,
    #[arg(long)]
    billing_code: Option<String>,
    #[arg(long = "label-id")]
    label_ids: Vec<String>,
    #[arg(long)]
    assignee_adapter_overrides_json: Option<String>,
    #[arg(long)]
    assignee_adapter_overrides_file: Option<PathBuf>,
    #[arg(long)]
    execution_workspace_settings_json: Option<String>,
    #[arg(long)]
    execution_workspace_settings_file: Option<PathBuf>,
}

#[derive(Args)]
struct IssueGetArgs {
    #[arg(long)]
    issue_id: String,
}

#[derive(Args)]
struct IssueUpdateArgs {
    #[arg(long)]
    issue_id: String,
    #[arg(long)]
    title: Option<String>,
    #[arg(long)]
    description: Option<String>,
    #[arg(long)]
    description_file: Option<PathBuf>,
    #[arg(long)]
    clear_description: bool,
    #[arg(long)]
    status: Option<String>,
    #[arg(long)]
    priority: Option<String>,
    #[arg(long)]
    project_id: Option<String>,
    #[arg(long)]
    clear_project_id: bool,
    #[arg(long)]
    parent_id: Option<String>,
    #[arg(long)]
    clear_parent_id: bool,
    #[arg(long)]
    assignee_agent_id: Option<String>,
    #[arg(long)]
    clear_assignee_agent_id: bool,
    #[arg(long)]
    assignee_user_id: Option<String>,
    #[arg(long)]
    clear_assignee_user_id: bool,
}

#[derive(Args)]
struct IssueCommentListArgs {
    #[arg(long)]
    issue_id: String,
}

#[derive(Args)]
struct IssueCommentAddArgs {
    #[arg(long)]
    company_id: String,
    #[arg(long)]
    issue_id: String,
    #[arg(long)]
    body: Option<String>,
    #[arg(long)]
    body_file: Option<PathBuf>,
    #[arg(long)]
    author_agent_id: Option<String>,
    #[arg(long)]
    author_user_id: Option<String>,
}

#[derive(Args)]
struct IssueAttachmentListArgs {
    #[arg(long)]
    issue_id: String,
}

#[derive(Args)]
struct IssueCheckoutArgs {
    #[arg(long)]
    issue_id: String,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cli = Cli::parse();

    let paths = match cli.base_dir {
        Some(base) => Paths::with_base_dir(base),
        None => Paths::new()?,
    };

    // Initialize logging before any async startup work so early failures are captured.
    init_logging(&cli.log_level, Some(paths.logs_dir().join("dev.jsonl")));

    let mut main_owns_shutdown = true;

    let result = match cli.command {
        Some(Commands::Start { foreground }) => {
            main_owns_shutdown = false;
            let config = Config::load(&paths)?;
            app::run_daemon(config, paths.clone(), foreground).await
        }
        None => {
            // Default to start in foreground if no command given
            main_owns_shutdown = false;
            let config = Config::load(&paths)?;
            app::run_daemon(config, paths.clone(), true).await
        }
        Some(Commands::Stop) => app::stop_daemon(&paths).await,
        Some(Commands::Status) => app::check_status(&paths).await,
        Some(Commands::Board { command }) => run_board_command(&paths, command).await,
    };

    if main_owns_shutdown || result.is_err() {
        shutdown();
    }

    result
}

async fn run_board_command(
    paths: &Paths,
    command: BoardCommands,
) -> Result<(), Box<dyn std::error::Error>> {
    match command {
        BoardCommands::HireAgent(args) => {
            let mut params = Map::new();
            params.insert("company_id".to_string(), Value::String(args.company_id));
            params.insert("name".to_string(), Value::String(args.name));
            if let Some(role) = args.role {
                params.insert("role".to_string(), Value::String(role));
            }
            insert_optional_string(&mut params, "title", args.title);
            insert_optional_string(&mut params, "icon", args.icon);
            insert_optional_string(&mut params, "reports_to", args.reports_to);
            insert_optional_string(&mut params, "capabilities", args.capabilities);
            insert_optional_string(&mut params, "adapter_type", args.adapter_type);
            if let Some(budget) = args.budget_monthly_cents {
                params.insert("budget_monthly_cents".to_string(), Value::from(budget));
            }
            insert_optional_string(
                &mut params,
                "requested_by_agent_id",
                args.requested_by_agent_id,
            );
            insert_optional_string(
                &mut params,
                "requested_by_user_id",
                args.requested_by_user_id,
            );
            insert_optional_string(&mut params, "requested_by_run_id", args.requested_by_run_id);
            if !args.source_issue_ids.is_empty() {
                params.insert(
                    "source_issue_ids".to_string(),
                    Value::Array(
                        args.source_issue_ids
                            .into_iter()
                            .map(Value::String)
                            .collect(),
                    ),
                );
            }
            insert_optional_json(
                &mut params,
                "adapter_config",
                read_optional_json_arg(
                    "adapter_config",
                    args.adapter_config_json,
                    args.adapter_config_file,
                )?,
            );
            insert_optional_json(
                &mut params,
                "runtime_config",
                read_optional_json_arg(
                    "runtime_config",
                    args.runtime_config_json,
                    args.runtime_config_file,
                )?,
            );
            insert_optional_json(
                &mut params,
                "permissions",
                read_optional_json_arg(
                    "permissions",
                    args.permissions_json,
                    args.permissions_file,
                )?,
            );
            insert_optional_json(
                &mut params,
                "metadata",
                read_optional_json_arg("metadata", args.metadata_json, args.metadata_file)?,
            );

            call_board(paths, Method::AgentHireCreate, Value::Object(params)).await
        }
        BoardCommands::IssueList(args) => {
            let mut params = Map::new();
            params.insert("company_id".to_string(), Value::String(args.company_id));
            insert_optional_string(&mut params, "project_id", args.project_id);
            insert_optional_string(&mut params, "parent_id", args.parent_id);
            insert_optional_string(&mut params, "assignee_agent_id", args.assignee_agent_id);
            if args.include_hidden {
                params.insert("include_hidden".to_string(), Value::Bool(true));
            }

            call_board(paths, Method::IssueList, Value::Object(params)).await
        }
        BoardCommands::IssueCreate(args) => {
            let mut params = Map::new();
            params.insert("company_id".to_string(), Value::String(args.company_id));
            params.insert("title".to_string(), Value::String(args.title));
            insert_optional_string(
                &mut params,
                "description",
                read_optional_text_arg("description", args.description, args.description_file)?,
            );
            insert_optional_string(&mut params, "status", args.status);
            insert_optional_string(&mut params, "priority", args.priority);
            insert_optional_string(&mut params, "project_id", args.project_id);
            insert_optional_string(&mut params, "goal_id", args.goal_id);
            insert_optional_string(&mut params, "parent_id", args.parent_id);
            insert_optional_string(&mut params, "assignee_agent_id", args.assignee_agent_id);
            insert_optional_string(&mut params, "assignee_user_id", args.assignee_user_id);
            insert_optional_string(&mut params, "created_by_agent_id", args.created_by_agent_id);
            insert_optional_string(&mut params, "created_by_user_id", args.created_by_user_id);
            insert_optional_string(&mut params, "billing_code", args.billing_code);
            if !args.label_ids.is_empty() {
                params.insert(
                    "label_ids".to_string(),
                    Value::Array(args.label_ids.into_iter().map(Value::String).collect()),
                );
            }
            insert_optional_json(
                &mut params,
                "assignee_adapter_overrides",
                read_optional_json_arg(
                    "assignee_adapter_overrides",
                    args.assignee_adapter_overrides_json,
                    args.assignee_adapter_overrides_file,
                )?,
            );
            insert_optional_json(
                &mut params,
                "execution_workspace_settings",
                read_optional_json_arg(
                    "execution_workspace_settings",
                    args.execution_workspace_settings_json,
                    args.execution_workspace_settings_file,
                )?,
            );

            call_board(paths, Method::IssueCreate, Value::Object(params)).await
        }
        BoardCommands::IssueGet(args) => {
            let mut params = Map::new();
            params.insert("issue_id".to_string(), Value::String(args.issue_id));
            call_board(paths, Method::IssueGet, Value::Object(params)).await
        }
        BoardCommands::IssueUpdate(args) => {
            ensure_not_conflicting(
                "description",
                args.clear_description,
                args.description.is_some() || args.description_file.is_some(),
            )?;
            ensure_not_conflicting(
                "project_id",
                args.clear_project_id,
                args.project_id.is_some(),
            )?;
            ensure_not_conflicting("parent_id", args.clear_parent_id, args.parent_id.is_some())?;
            ensure_not_conflicting(
                "assignee_agent_id",
                args.clear_assignee_agent_id,
                args.assignee_agent_id.is_some(),
            )?;
            ensure_not_conflicting(
                "assignee_user_id",
                args.clear_assignee_user_id,
                args.assignee_user_id.is_some(),
            )?;

            let mut params = Map::new();
            params.insert("issue_id".to_string(), Value::String(args.issue_id));
            insert_optional_string(&mut params, "title", args.title);
            if args.clear_description {
                params.insert("description".to_string(), Value::Null);
            } else {
                insert_optional_string(
                    &mut params,
                    "description",
                    read_optional_text_arg("description", args.description, args.description_file)?,
                );
            }
            insert_optional_string(&mut params, "status", args.status);
            insert_optional_string(&mut params, "priority", args.priority);
            insert_optional_nullable_string(
                &mut params,
                "project_id",
                args.project_id,
                args.clear_project_id,
            );
            insert_optional_nullable_string(
                &mut params,
                "parent_id",
                args.parent_id,
                args.clear_parent_id,
            );
            insert_optional_nullable_string(
                &mut params,
                "assignee_agent_id",
                args.assignee_agent_id,
                args.clear_assignee_agent_id,
            );
            insert_optional_nullable_string(
                &mut params,
                "assignee_user_id",
                args.assignee_user_id,
                args.clear_assignee_user_id,
            );

            call_board(paths, Method::IssueUpdate, Value::Object(params)).await
        }
        BoardCommands::IssueCommentList(args) => {
            let mut params = Map::new();
            params.insert("issue_id".to_string(), Value::String(args.issue_id));
            call_board(paths, Method::IssueCommentList, Value::Object(params)).await
        }
        BoardCommands::IssueCommentAdd(args) => {
            let body = read_required_text_arg("body", args.body, args.body_file)?;
            let mut params = Map::new();
            params.insert("company_id".to_string(), Value::String(args.company_id));
            params.insert("issue_id".to_string(), Value::String(args.issue_id));
            params.insert("body".to_string(), Value::String(body));
            insert_optional_string(&mut params, "author_agent_id", args.author_agent_id);
            insert_optional_string(&mut params, "author_user_id", args.author_user_id);

            call_board(paths, Method::IssueCommentAdd, Value::Object(params)).await
        }
        BoardCommands::IssueAttachmentList(args) => {
            let mut params = Map::new();
            params.insert("issue_id".to_string(), Value::String(args.issue_id));
            call_board(paths, Method::IssueAttachmentList, Value::Object(params)).await
        }
        BoardCommands::IssueCheckout(args) => {
            let mut params = Map::new();
            params.insert("issue_id".to_string(), Value::String(args.issue_id));
            call_board(paths, Method::IssueCheckout, Value::Object(params)).await
        }
    }
}

async fn call_board(
    paths: &Paths,
    method: Method,
    params: Value,
) -> Result<(), Box<dyn std::error::Error>> {
    let socket_path = paths.socket_file().to_string_lossy().to_string();
    let client = IpcClient::new(&socket_path);
    let response = client.call_method_with_params(method, params).await?;
    if let Some(error) = response.error {
        return Err(std::io::Error::other(error.message).into());
    }
    let payload = response.result.unwrap_or(Value::Null);
    println!("{}", serde_json::to_string_pretty(&payload)?);
    Ok(())
}

fn insert_optional_string(params: &mut Map<String, Value>, key: &str, value: Option<String>) {
    if let Some(value) = value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
    {
        params.insert(key.to_string(), Value::String(value));
    }
}

fn insert_optional_nullable_string(
    params: &mut Map<String, Value>,
    key: &str,
    value: Option<String>,
    clear: bool,
) {
    if clear {
        params.insert(key.to_string(), Value::Null);
    } else {
        insert_optional_string(params, key, value);
    }
}

fn insert_optional_json(params: &mut Map<String, Value>, key: &str, value: Option<Value>) {
    if let Some(value) = value {
        params.insert(key.to_string(), value);
    }
}

fn ensure_not_conflicting(
    field: &str,
    clear: bool,
    has_value: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    if clear && has_value {
        return Err(std::io::Error::other(format!(
            "Cannot set and clear {field} in the same command"
        ))
        .into());
    }
    Ok(())
}

fn read_optional_text_arg(
    field: &str,
    value: Option<String>,
    file: Option<PathBuf>,
) -> Result<Option<String>, Box<dyn std::error::Error>> {
    if value.is_some() && file.is_some() {
        return Err(std::io::Error::other(format!(
            "Provide either --{field} or --{field}-file, not both"
        ))
        .into());
    }
    if let Some(value) = value {
        let trimmed = value.trim().to_string();
        if trimmed.is_empty() {
            return Ok(None);
        }
        return Ok(Some(trimmed));
    }
    if let Some(file) = file {
        let content = std::fs::read_to_string(file)?;
        let trimmed = content.trim().to_string();
        if trimmed.is_empty() {
            return Ok(None);
        }
        return Ok(Some(trimmed));
    }
    Ok(None)
}

fn read_required_text_arg(
    field: &str,
    value: Option<String>,
    file: Option<PathBuf>,
) -> Result<String, Box<dyn std::error::Error>> {
    read_optional_text_arg(field, value, file)?.ok_or_else(|| {
        std::io::Error::other(format!("--{field} or --{field}-file is required")).into()
    })
}

fn read_optional_json_arg(
    field: &str,
    value: Option<String>,
    file: Option<PathBuf>,
) -> Result<Option<Value>, Box<dyn std::error::Error>> {
    let Some(raw) = read_optional_text_arg(field, value, file)? else {
        return Ok(None);
    };
    let parsed = serde_json::from_str(&raw)
        .map_err(|error| std::io::Error::other(format!("Invalid JSON for {field}: {error}")))?;
    Ok(Some(parsed))
}
