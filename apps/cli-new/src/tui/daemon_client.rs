//! IPC client wrapper for TUI usage.

use super::app::{
    ActiveSubAgent, ActiveTool, App, AuthStatus, ChatMessage, FileEntry, FileStatus, MessageRole,
    Repository, Session, SessionState, ToolHistoryEntry, ToolStatus,
};
use super::claude_events::ClaudeCodeMessage;
use anyhow::Result;
use daemon_config_and_utils::Paths;
use daemon_ipc::{Event as DaemonEvent, IpcClient, Method, StreamingSubscription};
use std::collections::HashMap;
use tokio::sync::mpsc;

impl App {
    /// Refresh all data from the daemon.
    pub async fn refresh_data(&mut self) -> Result<()> {
        let client = get_ipc_client()?;

        // Check if daemon is running
        if !client.is_daemon_running().await {
            self.daemon_connected = false;
            return Err(anyhow::anyhow!("Daemon is not running"));
        }

        self.daemon_connected = true;

        // Fetch auth status
        if let Ok(status) = fetch_auth_status(&client).await {
            self.auth_status = status;
        }

        // Fetch repositories
        if let Ok(repos) = fetch_repositories(&client).await {
            self.repositories = repos;

            // Fetch sessions for each repository
            for repo in &self.repositories {
                if let Ok(sessions) = fetch_sessions(&client, &repo.id).await {
                    self.sessions.insert(repo.id.clone(), sessions);
                }
            }
        }

        // Fetch git status for selected repository
        if let Some(repo) = self.selected_repo() {
            if let Ok((files, branch)) = fetch_git_status(&client, &repo.id).await {
                self.files = files;
                self.git_branch = branch;
            }
        }

        Ok(())
    }

    /// Create a new session for the selected repository.
    pub async fn create_session(&mut self, title: Option<&str>, is_worktree: bool) -> Result<()> {
        let repo_id = self
            .selected_repo()
            .map(|r| r.id.clone())
            .ok_or_else(|| anyhow::anyhow!("No repository selected"))?;

        let client = get_ipc_client()?;
        let params = serde_json::json!({
            "repository_id": repo_id,
            "title": title.unwrap_or("New session"),
            "is_worktree": is_worktree,
        });

        let response = client
            .call_method_with_params(Method::SessionCreate, params)
            .await?;

        if let Some(error) = &response.error {
            return Err(anyhow::anyhow!("{}", error.message));
        }

        // Extract the new session ID from the response
        let new_session_id = response
            .result
            .as_ref()
            .and_then(|r| r.get("id"))
            .and_then(|v| v.as_str())
            .map(String::from);

        // Refresh sessions for this repo
        if let Ok(sessions) = fetch_sessions(&client, &repo_id).await {
            self.sessions.insert(repo_id.clone(), sessions);
        }

        // Auto-focus the new session
        if let Some(session_id) = new_session_id {
            // Expand the repo to show sessions
            self.expanded_repos.insert(repo_id.clone());

            // Find the index of the new session in the sessions list
            let session_idx = self
                .sessions
                .get(&repo_id)
                .and_then(|sessions| sessions.iter().position(|s| s.id == session_id))
                .map(|idx| idx + 1) // +1 because idx 0 = repo, idx 1+ = sessions
                .unwrap_or(1);

            // Set the new session as selected
            self.selected_session_id = Some(session_id);
            self.selected_session_idx = session_idx;
        }

        Ok(())
    }

    /// Delete the selected session.
    pub async fn delete_session(&mut self) -> Result<()> {
        let session_id = self
            .selected_session_id
            .clone()
            .ok_or_else(|| anyhow::anyhow!("No session selected"))?;

        let repo_id = self
            .selected_repo()
            .map(|r| r.id.clone())
            .ok_or_else(|| anyhow::anyhow!("No repository selected"))?;

        let client = get_ipc_client()?;
        let params = serde_json::json!({ "id": session_id });

        let response = client
            .call_method_with_params(Method::SessionDelete, params)
            .await?;

        if let Some(error) = &response.error {
            return Err(anyhow::anyhow!("{}", error.message));
        }

        // Refresh sessions for this repo
        if let Ok(sessions) = fetch_sessions(&client, &repo_id).await {
            self.sessions.insert(repo_id, sessions);
        }

        // Remove per-session state
        self.session_states.remove(&session_id);

        self.selected_session_id = None;
        self.selected_session_idx = 0;

        Ok(())
    }

    /// Send a message in the current session.
    /// This invokes the Claude CLI and streams events to the database.
    pub async fn send_message(&mut self, content: &str) -> Result<()> {
        let session_id = self
            .selected_session_id
            .clone()
            .ok_or_else(|| anyhow::anyhow!("No session selected"))?;

        let client = get_ipc_client()?;
        let params = serde_json::json!({
            "session_id": session_id,
            "content": content,
        });

        // Call claude.send which spawns the Claude CLI
        // The daemon persists the user message before returning
        let response = client
            .call_method_with_params(Method::ClaudeSend, params)
            .await?;

        if let Some(error) = &response.error {
            return Err(anyhow::anyhow!("{}", error.message));
        }

        // Mark that we're waiting for Claude
        self.claude_running = true;

        // Fetch messages to ensure user message is visible
        // (daemon has already persisted it)
        self.fetch_messages().await?;

        Ok(())
    }

    /// Load a session's messages from the daemon.
    pub async fn fetch_session_data(&mut self, session_id: &str) -> Result<()> {
        // Clear tool state from previous session
        self.clear_tool_state();

        // Fetch current messages
        self.fetch_messages().await?;

        // Ensure session state exists in map and sync running flag
        let state = self
            .session_states
            .entry(session_id.to_string())
            .or_insert_with(SessionState::default);
        state.claude_running = self.claude_running;
        state.needs_message_refresh = false;

        Ok(())
    }

    /// Check if Claude is running for the current session.
    pub async fn check_claude_status(&mut self) -> Result<bool> {
        let session_id = match &self.selected_session_id {
            Some(id) => id.clone(),
            None => return Ok(false),
        };

        let client = get_ipc_client()?;
        let params = serde_json::json!({ "session_id": session_id });

        let response = client
            .call_method_with_params(Method::ClaudeStatus, params)
            .await?;

        if let Some(result) = &response.result {
            let is_running = result
                .get("is_running")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            self.claude_running = is_running;
            Ok(is_running)
        } else {
            Ok(false)
        }
    }

    /// Fetch latest messages for the current session.
    /// Messages are stored in chronological order by sequence_number.
    pub async fn fetch_events(&mut self) -> Result<()> {
        // Just fetch messages - they contain both user and assistant content
        self.fetch_messages().await
    }

    /// Fetch messages for the current session.
    /// Parses raw NDJSON and extracts displayable content, including tool history.
    pub async fn fetch_messages(&mut self) -> Result<()> {
        let session_id = self
            .selected_session_id
            .clone()
            .ok_or_else(|| anyhow::anyhow!("No session selected"))?;

        let client = get_ipc_client()?;
        let params = serde_json::json!({ "session_id": session_id });

        let response = client
            .call_method_with_params(Method::MessageList, params)
            .await?;

        if let Some(error) = &response.error {
            return Err(anyhow::anyhow!("{}", error.message));
        }

        if let Some(result) = &response.result {
            // Parse all raw messages first
            let raw_messages: Vec<_> = result
                .get("messages")
                .and_then(|v| v.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|m| {
                            let content = m.get("content").and_then(|v| v.as_str())?;
                            // Try to parse as Claude event, or wrap as raw user input
                            match ClaudeCodeMessage::from_json(content) {
                                Ok(parsed) => Some((parsed, None)),
                                Err(_) => Some((
                                    ClaudeCodeMessage::Result(super::claude_events::ResultMessage {
                                        subtype: None,
                                        is_error: None,
                                        result: None,
                                        duration_ms: None,
                                        duration_api_ms: None,
                                        num_turns: None,
                                        session_id: None,
                                        cost_usd: None,
                                        usage: None,
                                    }),
                                    Some(content.to_string()),
                                )),
                            }
                        })
                        .collect()
                })
                .unwrap_or_default();

            // Clear previous state
            self.messages.clear();
            self.tool_history.clear();

            // First pass: collect all tool results for status lookup
            let mut tool_results: HashMap<String, bool> = HashMap::new();
            for (msg, _) in &raw_messages {
                if let ClaudeCodeMessage::User(user) = msg {
                    for result in user.tool_results() {
                        tool_results.insert(result.tool_use_id.clone(), result.is_error);
                    }
                }
            }

            // Second pass: build messages and tool history
            for (msg, raw_content) in raw_messages {
                // Handle raw user input that couldn't be parsed
                if let Some(content) = raw_content {
                    self.messages.push(ChatMessage {
                        role: MessageRole::User,
                        content,
                    });
                    continue;
                }

                match msg {
                    ClaudeCodeMessage::Assistant(ref a) => {
                        // Extract text for display
                        let text = a.full_text();
                        if !text.is_empty() {
                            self.messages.push(ChatMessage {
                                role: MessageRole::Assistant,
                                content: text,
                            });
                        }

                        // Extract tools for history
                        let tool_uses = a.tool_uses();
                        if !tool_uses.is_empty() {
                            let mut tools = Vec::new();
                            let mut sub_agent: Option<ActiveSubAgent> = None;

                            for tool_use in tool_uses {
                                let status = match tool_results.get(&tool_use.id) {
                                    Some(true) => ToolStatus::Failed,
                                    Some(false) => ToolStatus::Completed,
                                    None => ToolStatus::Completed, // Assume completed if no result found
                                };

                                if let Some(task) = tool_use.as_task() {
                                    sub_agent = Some(ActiveSubAgent {
                                        tool_use_id: tool_use.id.clone(),
                                        subagent_type: task.subagent_type,
                                        description: task.description,
                                        child_tools: Vec::new(),
                                        status,
                                    });
                                } else {
                                    let tool = ActiveTool {
                                        tool_use_id: tool_use.id.clone(),
                                        tool_name: tool_use.name.clone(),
                                        status,
                                        input_preview: tool_use.input_preview(),
                                    };
                                    if let Some(ref mut agent) = sub_agent {
                                        agent.child_tools.push(tool);
                                    } else {
                                        tools.push(tool);
                                    }
                                }
                            }

                            if !tools.is_empty() || sub_agent.is_some() {
                                self.tool_history.push(ToolHistoryEntry {
                                    tools,
                                    sub_agent,
                                    after_message_idx: self.messages.len().saturating_sub(1),
                                });
                            }
                        }
                    }
                    ClaudeCodeMessage::Result(ref r) => {
                        // Show errors as system messages
                        if r.is_error == Some(true) {
                            if let Some(ref error_text) = r.result {
                                self.messages.push(ChatMessage {
                                    role: MessageRole::System,
                                    content: format!("Error: {}", error_text),
                                });
                            }
                        }
                    }
                    // System messages and User messages (tool results) are hidden
                    ClaudeCodeMessage::System(_)
                    | ClaudeCodeMessage::User(_)
                    | ClaudeCodeMessage::StreamEvent(_) => {}
                }
            }

            // Enable auto-scroll when new messages arrive
            self.chat_auto_scroll = true;

            // Update preview for sidebar display
            if let Some(ref session_id) = self.selected_session_id.clone() {
                let preview = self.get_session_preview(session_id, 40);
                if let Some(state) = self.session_states.get_mut(session_id) {
                    state.last_message_preview = preview;
                }
            }
        }

        Ok(())
    }

    /// Fetch diff for the selected file.
    pub async fn fetch_selected_file_diff(&mut self) -> Result<()> {
        let repo_id = self
            .selected_repo()
            .map(|r| r.id.clone())
            .ok_or_else(|| anyhow::anyhow!("No repository selected"))?;

        let file_path = self
            .files
            .get(self.selected_file_idx)
            .map(|f| f.path.clone())
            .ok_or_else(|| anyhow::anyhow!("No file selected"))?;

        let client = get_ipc_client()?;
        let (diff, additions, deletions) = fetch_file_diff(&client, &repo_id, &file_path).await?;

        self.selected_file_diff = if diff.is_empty() { None } else { Some(diff) };
        self.diff_additions = additions;
        self.diff_deletions = deletions;

        Ok(())
    }

    /// Refresh git status for the selected repository.
    pub async fn refresh_git_status(&mut self) -> Result<()> {
        let repo_id = self
            .selected_repo()
            .map(|r| r.id.clone())
            .ok_or_else(|| anyhow::anyhow!("No repository selected"))?;

        let client = get_ipc_client()?;
        let (files, branch) = fetch_git_status(&client, &repo_id).await?;

        self.files = files;
        self.git_branch = branch;
        self.selected_file_idx = 0;
        self.selected_file_diff = None;

        Ok(())
    }

    /// Run a terminal command.
    pub async fn run_terminal_command(&mut self, command: &str) -> Result<()> {
        let session_id = self
            .selected_session_id
            .clone()
            .ok_or_else(|| anyhow::anyhow!("No session selected"))?;

        let client = get_ipc_client()?;
        let params = serde_json::json!({
            "session_id": session_id,
            "command": command,
        });

        let response = client
            .call_method_with_params(Method::TerminalRun, params)
            .await?;

        if let Some(error) = &response.error {
            return Err(anyhow::anyhow!("{}", error.message));
        }

        // Clear previous output and mark as running
        self.terminal_output.clear();
        self.terminal_running = true;
        self.terminal_exit_code = None;
        self.terminal_input.clear();

        Ok(())
    }

    /// Stop the running terminal command.
    pub async fn stop_terminal(&mut self) -> Result<()> {
        let session_id = self
            .selected_session_id
            .clone()
            .ok_or_else(|| anyhow::anyhow!("No session selected"))?;

        let client = get_ipc_client()?;
        let params = serde_json::json!({ "session_id": session_id });

        let response = client
            .call_method_with_params(Method::TerminalStop, params)
            .await?;

        if let Some(error) = &response.error {
            return Err(anyhow::anyhow!("{}", error.message));
        }

        self.terminal_running = false;

        Ok(())
    }

    /// Check terminal status.
    pub async fn check_terminal_status(&mut self) -> Result<bool> {
        let session_id = match &self.selected_session_id {
            Some(id) => id.clone(),
            None => return Ok(false),
        };

        let client = get_ipc_client()?;
        let params = serde_json::json!({ "session_id": session_id });

        let response = client
            .call_method_with_params(Method::TerminalStatus, params)
            .await?;

        if let Some(result) = &response.result {
            let is_running = result
                .get("is_running")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            self.terminal_running = is_running;
            Ok(is_running)
        } else {
            Ok(false)
        }
    }

    /// Logout from the current session.
    pub async fn logout(&mut self) -> Result<()> {
        let client = get_ipc_client()?;
        let response = client.call_method(Method::AuthLogout).await?;

        if let Some(error) = &response.error {
            return Err(anyhow::anyhow!("{}", error.message));
        }

        // Clear auth status
        self.auth_status = AuthStatus::default();

        Ok(())
    }

    /// Start a streaming subscription for the current session.
    /// Events will be sent to the event_receiver channel.
    pub async fn start_subscription(&mut self) -> Result<()> {
        let session_id = self
            .selected_session_id
            .clone()
            .ok_or_else(|| anyhow::anyhow!("No session selected"))?;

        // Stop any existing subscription
        self.stop_subscription().await;

        let client = get_ipc_client()?;
        let subscription = client.subscribe(&session_id).await?;

        // Create channel for events
        let (tx, rx) = mpsc::channel::<DaemonEvent>(100);
        self.event_receiver = Some(rx);

        // Spawn task to forward events from subscription to channel
        let task = tokio::spawn(async move {
            forward_subscription_events(subscription, tx).await;
        });
        self.subscription_task = Some(task);

        Ok(())
    }

    /// Stop the current streaming subscription.
    pub async fn stop_subscription(&mut self) {
        // Cancel the forwarding task
        if let Some(task) = self.subscription_task.take() {
            task.abort();
        }
        // Drop the receiver (sender will be dropped when task ends)
        self.event_receiver = None;
    }

    /// Handle a daemon event from the streaming subscription.
    pub fn handle_daemon_event(&mut self, event: DaemonEvent) {
        use daemon_ipc::EventType;

        match event.event_type {
            EventType::ClaudeEvent => {
                // Parse the raw JSON data from the event
                if let Some(raw_json) = event.data.get("raw_json").and_then(|v| v.as_str()) {
                    self.handle_claude_event(raw_json);
                }
            }
            EventType::StatusChange => {
                // Update running status - status is a string: "idle", "running", "waiting", "error"
                if let Some(status) = event.data.get("status").and_then(|v| v.as_str()) {
                    let is_running = status == "running";
                    self.claude_running = is_running;
                    if !is_running {
                        // Agent stopped - clear streaming state
                        self.streaming_content = None;
                        // Move active tools to history
                        if !self.active_tools.is_empty() || self.active_sub_agent.is_some() {
                            self.tool_history.push(ToolHistoryEntry {
                                tools: std::mem::take(&mut self.active_tools),
                                sub_agent: self.active_sub_agent.take(),
                                after_message_idx: self.messages.len().saturating_sub(1),
                            });
                        }
                    }
                }
            }
            EventType::Message => {
                // New message was added - parse and add to UI
                if let Some(raw_json) = event.data.get("raw_json").and_then(|v| v.as_str()) {
                    self.handle_claude_event(raw_json);
                }
            }
            EventType::StreamingChunk => {
                // Real-time streaming content
                if let Some(content) = event.data.get("content").and_then(|v| v.as_str()) {
                    if let Some(ref mut streaming) = self.streaming_content {
                        streaming.push_str(content);
                    } else {
                        self.streaming_content = Some(content.to_string());
                    }
                }
            }
            EventType::TerminalOutput => {
                // Terminal output chunk
                if let Some(output) = event.data.get("output").and_then(|v| v.as_str()) {
                    self.terminal_output.push(output.to_string());
                }
            }
            EventType::TerminalFinished => {
                // Terminal command finished
                self.terminal_running = false;
                if let Some(exit_code) = event.data.get("exit_code").and_then(|v| v.as_i64()) {
                    self.terminal_exit_code = Some(exit_code as i32);
                }
            }
            EventType::SessionCreated | EventType::SessionDeleted => {
                // Session lifecycle events - could refresh session list
            }
            EventType::InitialState | EventType::Ping | EventType::AuthStateChanged => {
                // Handled by subscription setup or ignored
            }
        }
    }
}

/// Forward events from a streaming subscription to an mpsc channel.
async fn forward_subscription_events(
    mut subscription: StreamingSubscription,
    tx: mpsc::Sender<DaemonEvent>,
) {
    loop {
        match subscription.recv().await {
            Some(event) => {
                if tx.send(event).await.is_err() {
                    // Receiver dropped, stop forwarding
                    break;
                }
            }
            None => {
                // Subscription closed
                break;
            }
        }
    }
}

/// Get the IPC client for communicating with the daemon.
fn get_ipc_client() -> Result<IpcClient> {
    let paths = Paths::new()?;
    Ok(IpcClient::new(&paths.socket_file().to_string_lossy()))
}

/// Fetch authentication status from the daemon.
async fn fetch_auth_status(client: &IpcClient) -> Result<AuthStatus> {
    let response = client.call_method(Method::AuthStatus).await?;

    if let Some(result) = &response.result {
        // Check for "authenticated" first, then fall back to "logged_in"
        let authenticated = result
            .get("authenticated")
            .or_else(|| result.get("logged_in"))
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let user_id = result
            .get("user_id")
            .and_then(|v| v.as_str())
            .map(String::from);
        let user_email = result
            .get("email")
            .and_then(|v| v.as_str())
            .map(String::from);
        let expires_at = result
            .get("expires_at")
            .and_then(|v| v.as_str())
            .map(String::from);

        Ok(AuthStatus {
            authenticated,
            user_id,
            user_email,
            expires_at,
        })
    } else {
        Ok(AuthStatus::default())
    }
}

/// Fetch repositories from the daemon.
async fn fetch_repositories(client: &IpcClient) -> Result<Vec<Repository>> {
    let response = client.call_method(Method::RepositoryList).await?;

    if let Some(result) = &response.result {
        let repos = result
            .get("repositories")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|r| {
                        let id = r.get("id").and_then(|v| v.as_str())?;
                        let name = r.get("name").and_then(|v| v.as_str())?;
                        let path = r.get("path").and_then(|v| v.as_str())?;
                        Some(Repository {
                            id: id.to_string(),
                            name: name.to_string(),
                            path: path.to_string(),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();

        Ok(repos)
    } else {
        Ok(Vec::new())
    }
}

/// Fetch sessions for a repository from the daemon.
async fn fetch_sessions(client: &IpcClient, repository_id: &str) -> Result<Vec<Session>> {
    let params = serde_json::json!({ "repository_id": repository_id });
    let response = client
        .call_method_with_params(Method::SessionList, params)
        .await?;

    if let Some(result) = &response.result {
        let sessions = result
            .get("sessions")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|s| {
                        let id = s.get("id").and_then(|v| v.as_str())?;
                        let title = s
                            .get("title")
                            .and_then(|v| v.as_str())
                            .unwrap_or("Untitled");
                        let status = s.get("status").and_then(|v| v.as_str()).unwrap_or("active");
                        let last_accessed_at = s
                            .get("last_accessed_at")
                            .and_then(|v| v.as_str())
                            .map(String::from);

                        Some(Session {
                            id: id.to_string(),
                            title: title.to_string(),
                            status: status.to_string(),
                            last_accessed_at,
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();

        Ok(sessions)
    } else {
        Ok(Vec::new())
    }
}

/// Fetch git status from the daemon.
async fn fetch_git_status(client: &IpcClient, repository_id: &str) -> Result<(Vec<FileEntry>, Option<String>)> {
    let params = serde_json::json!({ "repository_id": repository_id });
    let response = client
        .call_method_with_params(Method::GitStatus, params)
        .await?;

    if let Some(result) = &response.result {
        let branch = result.get("branch").and_then(|v| v.as_str()).map(String::from);

        let files = result
            .get("files")
            .and_then(|v| v.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|f| {
                        let path = f.get("path").and_then(|v| v.as_str())?;
                        let status_str = f.get("status").and_then(|v| v.as_str()).unwrap_or("unchanged");
                        let staged = f.get("staged").and_then(|v| v.as_bool()).unwrap_or(false);

                        let status = match status_str {
                            "modified" => FileStatus::Modified,
                            "added" => FileStatus::Added,
                            "deleted" => FileStatus::Deleted,
                            "renamed" => FileStatus::Renamed,
                            "untracked" => FileStatus::Untracked,
                            "conflicted" => FileStatus::Conflicted,
                            _ => FileStatus::Unchanged,
                        };

                        Some(FileEntry {
                            path: path.to_string(),
                            status,
                            staged,
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();

        Ok((files, branch))
    } else {
        Ok((Vec::new(), None))
    }
}

/// Fetch diff for a specific file from the daemon.
async fn fetch_file_diff(client: &IpcClient, repository_id: &str, file_path: &str) -> Result<(String, u32, u32)> {
    let params = serde_json::json!({
        "repository_id": repository_id,
        "file_path": file_path,
        "max_lines": 2000,
    });
    let response = client
        .call_method_with_params(Method::GitDiffFile, params)
        .await?;

    if let Some(result) = &response.result {
        let diff = result.get("diff").and_then(|v| v.as_str()).unwrap_or("").to_string();
        let additions = result.get("additions").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        let deletions = result.get("deletions").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
        Ok((diff, additions, deletions))
    } else {
        Ok((String::new(), 0, 0))
    }
}

