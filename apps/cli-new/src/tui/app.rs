//! Application state and data structures for the TUI.

#![allow(dead_code)]

use super::claude_events::{AssistantMessage, ClaudeCodeMessage, ToolUseBlock};
use super::theme::{Theme, ThemeMode};
use daemon_ipc::Event as DaemonEvent;
use std::collections::{HashMap, HashSet};
use tokio::sync::mpsc;

/// Per-session state that gets saved/restored on session switch.
pub struct SessionState {
    pub messages: Vec<ChatMessage>,
    pub streaming_content: Option<String>,
    pub claude_running: bool,
    pub spinner_frame: usize,
    pub active_tools: Vec<ActiveTool>,
    pub active_sub_agent: Option<ActiveSubAgent>,
    pub pending_prompt: Option<PendingPrompt>,
    pub tool_history: Vec<ToolHistoryEntry>,
    pub chat_scroll_offset: u16,
    pub chat_auto_scroll: bool,
    pub terminal_output: Vec<String>,
    pub terminal_running: bool,
    pub terminal_exit_code: Option<i32>,
    pub terminal_input: String,
    pub needs_message_refresh: bool,
    /// Last message preview for sidebar display
    pub last_message_preview: Option<String>,
}

impl Default for SessionState {
    fn default() -> Self {
        Self {
            messages: Vec::new(),
            streaming_content: None,
            claude_running: false,
            spinner_frame: 0,
            active_tools: Vec::new(),
            active_sub_agent: None,
            pending_prompt: None,
            tool_history: Vec::new(),
            chat_scroll_offset: 0,
            chat_auto_scroll: true,
            terminal_output: Vec::new(),
            terminal_running: false,
            terminal_exit_code: None,
            terminal_input: String::new(),
            needs_message_refresh: true,
            last_message_preview: None,
        }
    }
}

/// Status of a tool execution.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ToolStatus {
    Running,
    Completed,
    Failed,
}

/// Active tool being executed by Claude.
#[derive(Debug, Clone)]
pub struct ActiveTool {
    pub tool_use_id: String,
    pub tool_name: String,
    pub status: ToolStatus,
    pub input_preview: Option<String>,
}

/// Active sub-agent (Task tool with subagent_type).
#[derive(Debug, Clone)]
pub struct ActiveSubAgent {
    pub tool_use_id: String,
    pub subagent_type: String,
    pub description: Option<String>,
    pub child_tools: Vec<ActiveTool>,
    pub status: ToolStatus,
}

/// A completed tool run to display in chat history.
#[derive(Debug, Clone)]
pub struct ToolHistoryEntry {
    pub tools: Vec<ActiveTool>,
    pub sub_agent: Option<ActiveSubAgent>,
    /// Message index this tool group appeared after
    pub after_message_idx: usize,
}

/// Prompt option for AskUserQuestion.
#[derive(Debug, Clone)]
pub struct PromptOption {
    pub label: String,
    pub description: Option<String>,
}

/// Pending prompt from AskUserQuestion tool.
#[derive(Debug, Clone)]
pub struct PendingPrompt {
    pub tool_use_id: String,
    pub question: String,
    pub options: Vec<PromptOption>,
    pub selected_option: usize,
}

/// Main application state.
pub struct App {
    // Navigation
    pub active_panel: Panel,
    pub should_quit: bool,
    pub input_mode: InputMode,

    // Data
    pub repositories: Vec<Repository>,
    pub sessions: HashMap<String, Vec<Session>>,
    pub messages: Vec<ChatMessage>,

    // Selection
    pub selected_repo_idx: usize,
    pub selected_session_idx: usize,
    pub expanded_repos: HashSet<String>,
    pub selected_session_id: Option<String>,

    // UI state
    pub chat_input: String,
    pub chat_scroll_offset: u16,
    pub chat_auto_scroll: bool,
    pub sidebar_scroll: usize,

    // Version control panel
    pub vc_tab: VcTab,
    pub vc_focus: VcFocus,
    pub selected_file_idx: usize,
    pub files: Vec<FileEntry>,
    pub git_branch: Option<String>,
    pub selected_file_diff: Option<String>,
    pub diff_additions: u32,
    pub diff_deletions: u32,

    // Terminal
    pub terminal_output: Vec<String>,
    pub terminal_running: bool,
    pub terminal_input: String,
    pub terminal_exit_code: Option<i32>,
    pub terminal_scroll: usize,

    // Daemon
    pub daemon_connected: bool,
    pub auth_status: AuthStatus,

    // Claude
    pub claude_running: bool,
    pub spinner_frame: usize,

    // Streaming content (in-progress assistant response)
    pub streaming_content: Option<String>,

    // Tool activity tracking
    pub active_tools: Vec<ActiveTool>,
    pub active_sub_agent: Option<ActiveSubAgent>,
    pub pending_prompt: Option<PendingPrompt>,

    /// History of completed tool runs (persists in chat)
    pub tool_history: Vec<ToolHistoryEntry>,

    // Per-session state map (for background sessions)
    pub session_states: HashMap<String, SessionState>,

    // Status
    pub status_message: Option<String>,

    // Theme
    pub theme: Theme,

    // Account dialog
    pub show_account_dialog: bool,
    pub account_dialog_selected: usize,

    // Streaming subscription
    pub event_receiver: Option<mpsc::Receiver<DaemonEvent>>,
    pub subscription_task: Option<tokio::task::JoinHandle<()>>,
}

/// Active panel in the UI.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Panel {
    Sidebar,
    Chat,
    VersionControl,
}

/// Input mode for the chat panel.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputMode {
    Normal,
    Editing,
    Prompt,
}

/// Authentication status.
#[derive(Debug, Clone, Default)]
pub struct AuthStatus {
    pub authenticated: bool,
    pub user_id: Option<String>,
    pub user_email: Option<String>,
    pub expires_at: Option<String>,
}

/// Repository data.
#[derive(Debug, Clone)]
pub struct Repository {
    pub id: String,
    pub name: String,
    pub path: String,
}

/// Session data.
#[derive(Debug, Clone)]
pub struct Session {
    pub id: String,
    pub title: String,
    pub status: String,
    pub last_accessed_at: Option<String>,
}

/// Chat message data.
#[derive(Debug, Clone)]
pub struct ChatMessage {
    pub role: MessageRole,
    pub content: String,
}

/// Message role (user or assistant).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MessageRole {
    User,
    Assistant,
    System,
}

/// Version control tab.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VcTab {
    Changes,
    AllFiles,
}

/// Version control panel focus area.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum VcFocus {
    #[default]
    FileList,
    Diff,
    Terminal,
}

/// File entry in version control.
#[derive(Debug, Clone)]
pub struct FileEntry {
    pub path: String,
    pub status: FileStatus,
    pub staged: bool,
}

/// File status in git.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileStatus {
    Modified,
    Added,
    Deleted,
    Renamed,
    Untracked,
    Conflicted,
    Unchanged,
}

/// Compute preview from session state components.
/// Priority: active sub-agent > active tools > streaming content > last message.
fn compute_session_preview(
    active_sub_agent: &Option<ActiveSubAgent>,
    active_tools: &[ActiveTool],
    streaming_content: Option<&str>,
    messages: &[ChatMessage],
    max_len: usize,
) -> Option<String> {
    use super::ui::format_message_preview;

    // 1. Check for active sub-agent
    if let Some(ref agent) = active_sub_agent {
        if agent.status == ToolStatus::Running {
            let desc = agent
                .description
                .as_deref()
                .unwrap_or(&agent.subagent_type);
            return Some(format_message_preview(
                &format!("[{}] {}", agent.subagent_type, desc),
                max_len,
            ));
        }
    }

    // 2. Check for active tools
    let running_tools: Vec<_> = active_tools
        .iter()
        .filter(|t| t.status == ToolStatus::Running)
        .collect();
    if !running_tools.is_empty() {
        let tool = running_tools.last().unwrap();
        let preview = if let Some(ref input) = tool.input_preview {
            format!("[{}] {}", tool.tool_name, input)
        } else {
            format!("[{}]", tool.tool_name)
        };
        return Some(format_message_preview(&preview, max_len));
    }

    // 3. Check for streaming content
    if let Some(content) = streaming_content {
        if !content.is_empty() {
            return Some(format_message_preview(content, max_len));
        }
    }

    // 4. Fall back to last message
    messages
        .last()
        .map(|m| format_message_preview(&m.content, max_len))
}

impl App {
    /// Create a new application state with the specified theme mode.
    pub async fn new(theme_mode: ThemeMode) -> Self {
        Self {
            // Navigation
            active_panel: Panel::Sidebar,
            should_quit: false,
            input_mode: InputMode::Normal,

            // Data
            repositories: Vec::new(),
            sessions: HashMap::new(),
            messages: Vec::new(),

            // Selection
            selected_repo_idx: 0,
            selected_session_idx: 0,
            expanded_repos: HashSet::new(),
            selected_session_id: None,

            // UI state
            chat_input: String::new(),
            chat_scroll_offset: 0,
            chat_auto_scroll: true,
            sidebar_scroll: 0,

            // Version control
            vc_tab: VcTab::Changes,
            vc_focus: VcFocus::default(),
            selected_file_idx: 0,
            files: Vec::new(),
            git_branch: None,
            selected_file_diff: None,
            diff_additions: 0,
            diff_deletions: 0,

            // Terminal
            terminal_output: Vec::new(),
            terminal_running: false,
            terminal_input: String::new(),
            terminal_exit_code: None,
            terminal_scroll: 0,

            // Daemon
            daemon_connected: false,
            auth_status: AuthStatus::default(),

            // Claude
            claude_running: false,
            spinner_frame: 0,

            // Streaming
            streaming_content: None,

            // Tool activity
            active_tools: Vec::new(),
            active_sub_agent: None,
            pending_prompt: None,
            tool_history: Vec::new(),

            // Per-session state
            session_states: HashMap::new(),

            // Status
            status_message: None,

            // Theme
            theme: Theme::from_mode(theme_mode),

            // Account dialog
            show_account_dialog: false,
            account_dialog_selected: 0,

            // Streaming subscription
            event_receiver: None,
            subscription_task: None,
        }
    }

    /// Check if we should poll for new messages.
    /// Returns true if Claude is running and we should fetch messages.
    pub fn should_poll_messages(&self) -> bool {
        self.claude_running
    }

    /// Handle a raw Claude event JSON string by parsing it into typed messages.
    pub fn handle_claude_event(&mut self, raw_json: &str) {
        let msg = match ClaudeCodeMessage::from_json(raw_json) {
            Ok(m) => m,
            Err(_) => return, // Skip unparseable events
        };

        match msg {
            ClaudeCodeMessage::Assistant(ref assistant) => {
                self.handle_assistant_message(assistant);
            }
            ClaudeCodeMessage::User(ref user) => {
                // Tool results - update tool status
                for result in user.tool_results() {
                    let status = if result.is_error {
                        ToolStatus::Failed
                    } else {
                        ToolStatus::Completed
                    };
                    self.update_tool_status(&result.tool_use_id, status);
                }
            }
            ClaudeCodeMessage::Result(ref result) => {
                // Turn complete - move tools to history instead of clearing
                self.streaming_content = None;

                // Move completed tools to history (instead of clearing)
                if !self.active_tools.is_empty() || self.active_sub_agent.is_some() {
                    self.tool_history.push(ToolHistoryEntry {
                        tools: std::mem::take(&mut self.active_tools),
                        sub_agent: self.active_sub_agent.take(),
                        after_message_idx: self.messages.len().saturating_sub(1),
                    });
                }

                // Check for error
                if result.is_error == Some(true) {
                    if let Some(ref error_msg) = result.result {
                        self.set_status_message(format!("Error: {}", error_msg));
                    }
                }
            }
            ClaudeCodeMessage::System(_) => {
                // System messages - no TUI action needed
            }
            ClaudeCodeMessage::StreamEvent(ref stream_event) => {
                // Handle streaming deltas for real-time display
                self.handle_stream_event(stream_event);
            }
        }
    }

    /// Handle a streaming event for real-time content display.
    fn handle_stream_event(&mut self, stream_event: &super::claude_events::StreamEventMessage) {
        use super::claude_events::{ContentDelta, StreamEvent};

        match &stream_event.event {
            StreamEvent::ContentBlockDelta { delta, .. } => {
                match delta {
                    ContentDelta::TextDelta { text } => {
                        // Append text to streaming content
                        if let Some(ref mut content) = self.streaming_content {
                            content.push_str(text);
                        } else {
                            self.streaming_content = Some(text.clone());
                        }
                    }
                    ContentDelta::InputJsonDelta { .. } => {
                        // Tool input deltas - could update tool preview
                    }
                    ContentDelta::Unknown => {}
                }
            }
            StreamEvent::ContentBlockStart { .. } => {
                // New content block starting
            }
            StreamEvent::ContentBlockStop { .. } => {
                // Content block finished
            }
            StreamEvent::MessageStart { .. } => {
                // New message starting - clear streaming content
                self.streaming_content = None;
            }
            StreamEvent::MessageDelta { .. } => {
                // Message metadata update
            }
            StreamEvent::MessageStop => {
                // Message complete - streaming content will be replaced by final message
            }
            StreamEvent::Unknown => {}
        }
    }

    /// Handle an assistant message - extract tools and text.
    fn handle_assistant_message(&mut self, assistant: &AssistantMessage) {
        // Update streaming content with full text
        let full_text = assistant.full_text();
        if !full_text.is_empty() {
            self.streaming_content = Some(full_text);
        }

        // Process tool uses
        for tool_use in assistant.tool_uses() {
            self.handle_tool_use(tool_use);
        }
    }

    /// Handle a tool use block.
    fn handle_tool_use(&mut self, tool_use: &ToolUseBlock) {
        // Check for Task (sub-agent)
        if let Some(task_input) = tool_use.as_task() {
            self.active_sub_agent = Some(ActiveSubAgent {
                tool_use_id: tool_use.id.clone(),
                subagent_type: task_input.subagent_type,
                description: task_input.description,
                child_tools: Vec::new(),
                status: ToolStatus::Running,
            });
            return;
        }

        // Check for AskUserQuestion (prompt)
        if let Some(ask_input) = tool_use.as_ask_user_question() {
            if let Some(first_question) = ask_input.questions.first() {
                let options: Vec<PromptOption> = first_question
                    .options
                    .iter()
                    .map(|opt| PromptOption {
                        label: opt.label.clone(),
                        description: opt.description.clone(),
                    })
                    .collect();

                self.pending_prompt = Some(PendingPrompt {
                    tool_use_id: tool_use.id.clone(),
                    question: first_question.question.clone(),
                    options,
                    selected_option: 0,
                });
            }
            return;
        }

        // Regular tool - add to active tools with input preview
        let tool = ActiveTool {
            tool_use_id: tool_use.id.clone(),
            tool_name: tool_use.name.clone(),
            status: ToolStatus::Running,
            input_preview: tool_use.input_preview(),
        };

        // Add to sub-agent child tools if one is active, otherwise to main list
        if let Some(ref mut sub_agent) = self.active_sub_agent {
            sub_agent.child_tools.push(tool);
        } else {
            self.active_tools.push(tool);
        }
    }

    /// Update the status of a tool by its ID.
    fn update_tool_status(&mut self, tool_use_id: &str, status: ToolStatus) {
        // Check if this is the sub-agent completing
        if let Some(ref mut sub_agent) = self.active_sub_agent {
            if sub_agent.tool_use_id == tool_use_id {
                sub_agent.status = status;
                return;
            }
            // Check child tools
            for tool in &mut sub_agent.child_tools {
                if tool.tool_use_id == tool_use_id {
                    tool.status = status;
                    return;
                }
            }
        }

        // Check main tools list
        for tool in &mut self.active_tools {
            if tool.tool_use_id == tool_use_id {
                tool.status = status;
                return;
            }
        }
    }

    /// Clear all tool-related state. Call when switching sessions.
    pub fn clear_tool_state(&mut self) {
        self.active_tools.clear();
        self.active_sub_agent = None;
        self.tool_history.clear();
        self.streaming_content = None;
        self.pending_prompt = None;
    }

    /// Set a status message.
    pub fn set_status_message(&mut self, message: String) {
        self.status_message = Some(message);
    }

    /// Clear the status message.
    pub fn clear_status_message(&mut self) {
        self.status_message = None;
    }

    /// Get the currently selected repository.
    pub fn selected_repo(&self) -> Option<&Repository> {
        self.repositories.get(self.selected_repo_idx)
    }

    /// Get sessions for the selected repository.
    pub fn selected_repo_sessions(&self) -> Option<&Vec<Session>> {
        self.selected_repo().and_then(|r| self.sessions.get(&r.id))
    }

    /// Toggle expansion of the selected repository.
    pub fn toggle_repo_expansion(&mut self) {
        if let Some(repo) = self.selected_repo() {
            let repo_id = repo.id.clone();
            if self.expanded_repos.contains(&repo_id) {
                self.expanded_repos.remove(&repo_id);
            } else {
                self.expanded_repos.insert(repo_id);
            }
        }
    }

    /// Check if a repository is expanded.
    pub fn is_repo_expanded(&self, repo_id: &str) -> bool {
        self.expanded_repos.contains(repo_id)
    }

    /// Move to next panel.
    pub fn next_panel(&mut self) {
        self.active_panel = match self.active_panel {
            Panel::Sidebar => Panel::Chat,
            Panel::Chat => Panel::VersionControl,
            Panel::VersionControl => Panel::Sidebar,
        };
    }

    /// Move to previous panel.
    pub fn prev_panel(&mut self) {
        self.active_panel = match self.active_panel {
            Panel::Sidebar => Panel::VersionControl,
            Panel::Chat => Panel::Sidebar,
            Panel::VersionControl => Panel::Chat,
        };
    }

    /// Move selection down in the sidebar.
    pub fn sidebar_down(&mut self) {
        // Count total items (repos + their sessions if expanded)
        let total = self.sidebar_item_count();
        if total > 0 {
            let current = self.sidebar_selection_index();
            let new_idx = (current + 1) % total;
            self.set_sidebar_selection(new_idx);
        }
    }

    /// Move selection up in the sidebar.
    pub fn sidebar_up(&mut self) {
        let total = self.sidebar_item_count();
        if total > 0 {
            let current = self.sidebar_selection_index();
            let new_idx = if current == 0 { total - 1 } else { current - 1 };
            self.set_sidebar_selection(new_idx);
        }
    }

    /// Count total items in sidebar.
    fn sidebar_item_count(&self) -> usize {
        let mut count = 0;
        for repo in &self.repositories {
            count += 1; // The repo itself
            if self.is_repo_expanded(&repo.id) {
                if let Some(sessions) = self.sessions.get(&repo.id) {
                    count += sessions.len();
                }
            }
        }
        count
    }

    /// Get current sidebar selection index.
    fn sidebar_selection_index(&self) -> usize {
        let mut idx = 0;
        for (i, repo) in self.repositories.iter().enumerate() {
            if i == self.selected_repo_idx && self.selected_session_idx == 0 {
                return idx;
            }
            idx += 1;
            if self.is_repo_expanded(&repo.id) {
                if let Some(sessions) = self.sessions.get(&repo.id) {
                    if i == self.selected_repo_idx && self.selected_session_idx > 0 {
                        return idx + self.selected_session_idx - 1;
                    }
                    idx += sessions.len();
                }
            }
        }
        idx
    }

    /// Set sidebar selection from flat index.
    fn set_sidebar_selection(&mut self, flat_idx: usize) {
        let mut idx = 0;
        for (i, repo) in self.repositories.iter().enumerate() {
            if idx == flat_idx {
                self.selected_repo_idx = i;
                self.selected_session_idx = 0;
                self.selected_session_id = None;
                return;
            }
            idx += 1;
            if self.is_repo_expanded(&repo.id) {
                if let Some(sessions) = self.sessions.get(&repo.id) {
                    for (j, session) in sessions.iter().enumerate() {
                        if idx == flat_idx {
                            self.selected_repo_idx = i;
                            self.selected_session_idx = j + 1;
                            self.selected_session_id = Some(session.id.clone());
                            return;
                        }
                        idx += 1;
                    }
                }
            }
        }
    }

    /// Toggle version control tab.
    pub fn toggle_vc_tab(&mut self) {
        self.vc_tab = match self.vc_tab {
            VcTab::Changes => VcTab::AllFiles,
            VcTab::AllFiles => VcTab::Changes,
        };
    }

    /// Enter edit mode.
    pub fn enter_edit_mode(&mut self) {
        self.input_mode = InputMode::Editing;
    }

    /// Exit edit mode.
    pub fn exit_edit_mode(&mut self) {
        self.input_mode = InputMode::Normal;
    }

    /// Get the current spinner character for loading animation.
    pub fn spinner_char(&self) -> char {
        const SPINNER_FRAMES: [char; 10] = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
        SPINNER_FRAMES[self.spinner_frame % SPINNER_FRAMES.len()]
    }

    /// Advance the spinner frame (call on each render when claude_running is true).
    pub fn advance_spinner(&mut self) {
        self.spinner_frame = self.spinner_frame.wrapping_add(1);
    }

    /// Toggle the account dialog visibility.
    pub fn toggle_account_dialog(&mut self) {
        self.show_account_dialog = !self.show_account_dialog;
        self.account_dialog_selected = 0;
    }

    /// Close the account dialog.
    pub fn close_account_dialog(&mut self) {
        self.show_account_dialog = false;
        self.account_dialog_selected = 0;
    }

    /// Save the current top-level session fields into the session_states map.
    pub fn save_active_session(&mut self) {
        if let Some(ref session_id) = self.selected_session_id {
            let state = self
                .session_states
                .entry(session_id.clone())
                .or_insert_with(SessionState::default);

            state.messages = std::mem::take(&mut self.messages);
            state.streaming_content = self.streaming_content.take();
            state.claude_running = self.claude_running;
            state.spinner_frame = self.spinner_frame;
            state.active_tools = std::mem::take(&mut self.active_tools);
            state.active_sub_agent = self.active_sub_agent.take();
            state.pending_prompt = self.pending_prompt.take();
            state.tool_history = std::mem::take(&mut self.tool_history);
            state.chat_scroll_offset = self.chat_scroll_offset;
            state.chat_auto_scroll = self.chat_auto_scroll;
            state.terminal_output = std::mem::take(&mut self.terminal_output);
            state.terminal_running = self.terminal_running;
            state.terminal_exit_code = self.terminal_exit_code.take();
            state.terminal_input = std::mem::take(&mut self.terminal_input);
        }
    }

    /// Load a session's state from the map into top-level fields.
    /// Returns true if the session needs a message refresh (first load).
    fn load_session(&mut self, session_id: &str) -> bool {
        if let Some(mut state) = self.session_states.remove(session_id) {
            let needs_refresh = state.needs_message_refresh;

            self.messages = std::mem::take(&mut state.messages);
            self.streaming_content = state.streaming_content.take();
            self.claude_running = state.claude_running;
            self.spinner_frame = state.spinner_frame;
            self.active_tools = std::mem::take(&mut state.active_tools);
            self.active_sub_agent = state.active_sub_agent.take();
            self.pending_prompt = state.pending_prompt.take();
            self.tool_history = std::mem::take(&mut state.tool_history);
            self.chat_scroll_offset = state.chat_scroll_offset;
            self.chat_auto_scroll = state.chat_auto_scroll;
            self.terminal_output = std::mem::take(&mut state.terminal_output);
            self.terminal_running = state.terminal_running;
            self.terminal_exit_code = state.terminal_exit_code.take();
            self.terminal_input = std::mem::take(&mut state.terminal_input);

            // Re-insert the (now emptied) state so the key stays in the map
            state.needs_message_refresh = false;
            self.session_states.insert(session_id.to_string(), state);

            needs_refresh
        } else {
            // First time visiting this session — reset to defaults
            self.messages.clear();
            self.streaming_content = None;
            self.claude_running = false;
            self.spinner_frame = 0;
            self.active_tools.clear();
            self.active_sub_agent = None;
            self.pending_prompt = None;
            self.tool_history.clear();
            self.chat_scroll_offset = 0;
            self.chat_auto_scroll = true;
            self.terminal_output.clear();
            self.terminal_running = false;
            self.terminal_exit_code = None;
            self.terminal_input.clear();

            true // needs message refresh
        }
    }

    /// Switch the active session. Saves the current session state and loads the new one.
    /// Returns true if the new session needs a message fetch.
    pub fn switch_session(&mut self, new_session_id: &str) -> bool {
        // No-op if already on this session
        if self.selected_session_id.as_deref() == Some(new_session_id) {
            return false;
        }

        self.save_active_session();
        let needs_refresh = self.load_session(new_session_id);
        self.selected_session_id = Some(new_session_id.to_string());
        needs_refresh
    }

    /// Check if Claude is running for a given session.
    pub fn is_session_running(&self, session_id: &str) -> bool {
        if self.selected_session_id.as_deref() == Some(session_id) {
            return self.claude_running;
        }
        self.session_states
            .get(session_id)
            .map(|s| s.claude_running)
            .unwrap_or(false)
    }

    /// Get last message preview for sidebar display.
    /// Priority: active sub-agent > active tools > streaming content > last message.
    /// For background sessions: returns stored preview.
    pub fn get_session_preview(&self, session_id: &str, max_len: usize) -> Option<String> {
        // Active session - compute from top-level state
        if self.selected_session_id.as_deref() == Some(session_id) {
            return compute_session_preview(
                &self.active_sub_agent,
                &self.active_tools,
                self.streaming_content.as_deref(),
                &self.messages,
                max_len,
            );
        }

        // Background session - use stored preview
        self.session_states
            .get(session_id)
            .and_then(|s| s.last_message_preview.clone())
    }

}

impl FileStatus {
    /// Get the display character for this status.
    pub fn display_char(&self) -> char {
        match self {
            FileStatus::Modified => 'M',
            FileStatus::Added => 'A',
            FileStatus::Deleted => 'D',
            FileStatus::Renamed => 'R',
            FileStatus::Untracked => '?',
            FileStatus::Conflicted => 'U',
            FileStatus::Unchanged => ' ',
        }
    }
}
