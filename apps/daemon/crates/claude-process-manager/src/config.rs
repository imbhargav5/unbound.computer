//! Configuration for Claude CLI processes.

/// Default allowed tools for Claude CLI.
pub const DEFAULT_ALLOWED_TOOLS: &str = "AskUserQuestion,Bash,TaskOutput,Edit,ExitPlanMode,Glob,Grep,KillShell,MCPSearch,NotebookEdit,Read,Skill,Task,TaskCreate,TaskGet,TaskList,TaskUpdate,WebFetch,WebSearch,Write";

/// Configuration for spawning a Claude process.
#[derive(Debug, Clone)]
pub struct ClaudeConfig {
    /// The message/prompt to send to Claude.
    pub message: String,

    /// The working directory for the Claude process.
    pub working_dir: String,

    /// Optional Claude session ID to resume.
    pub resume_session_id: Option<String>,

    /// Optional custom allowed tools (uses DEFAULT_ALLOWED_TOOLS if None).
    pub allowed_tools: Option<String>,

    /// Optional permission mode for Claude CLI.
    pub permission_mode: Option<PermissionMode>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PermissionMode {
    Plan,
}

impl ClaudeConfig {
    /// Create a new configuration.
    pub fn new(message: impl Into<String>, working_dir: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            working_dir: working_dir.into(),
            resume_session_id: None,
            allowed_tools: None,
            permission_mode: None,
        }
    }

    /// Set the session ID to resume.
    pub fn with_resume_session(mut self, session_id: impl Into<String>) -> Self {
        self.resume_session_id = Some(session_id.into());
        self
    }

    /// Set custom allowed tools.
    pub fn with_allowed_tools(mut self, tools: impl Into<String>) -> Self {
        self.allowed_tools = Some(tools.into());
        self
    }

    /// Set permission mode.
    pub fn with_permission_mode(mut self, permission_mode: PermissionMode) -> Self {
        self.permission_mode = Some(permission_mode);
        self
    }

    /// Get the allowed tools string.
    pub fn allowed_tools(&self) -> &str {
        self.allowed_tools
            .as_deref()
            .unwrap_or(DEFAULT_ALLOWED_TOOLS)
    }

    /// Build the Claude CLI command string.
    pub(crate) fn build_command(&self) -> String {
        let escaped_message = shell_escape(&self.message);
        let allowed_tools = self.allowed_tools();

        let mut cmd = format!(
            "claude -p {} --verbose --output-format stream-json --allowedTools {}",
            escaped_message, allowed_tools
        );

        if let Some(ref session_id) = self.resume_session_id {
            cmd.push_str(&format!(" -r {}", session_id));
        }

        if matches!(self.permission_mode, Some(PermissionMode::Plan)) {
            cmd.push_str(" --permission-mode plan");
        }

        cmd
    }
}

/// Escape a string for shell usage.
fn shell_escape(s: &str) -> String {
    // Use single quotes and escape any single quotes within
    let escaped = s.replace('\'', "'\"'\"'");
    format!("'{}'", escaped)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_new() {
        let config = ClaudeConfig::new("Hello", "/tmp");
        assert_eq!(config.message, "Hello");
        assert_eq!(config.working_dir, "/tmp");
        assert!(config.resume_session_id.is_none());
        assert!(config.allowed_tools.is_none());
        assert!(config.permission_mode.is_none());
    }

    #[test]
    fn test_config_with_resume() {
        let config = ClaudeConfig::new("Hello", "/tmp").with_resume_session("session-123");
        assert_eq!(config.resume_session_id, Some("session-123".to_string()));
    }

    #[test]
    fn test_build_command_basic() {
        let config = ClaudeConfig::new("Hello world", "/tmp");
        let cmd = config.build_command();
        assert!(cmd.contains("claude -p 'Hello world'"));
        assert!(cmd.contains("--output-format stream-json"));
        assert!(cmd.contains("--allowedTools"));
    }

    #[test]
    fn test_build_command_with_resume() {
        let config = ClaudeConfig::new("Hello", "/tmp").with_resume_session("sess-abc");
        let cmd = config.build_command();
        assert!(cmd.contains("-r sess-abc"));
    }

    #[test]
    fn test_build_command_with_permission_mode_plan() {
        let config = ClaudeConfig::new("Hello", "/tmp").with_permission_mode(PermissionMode::Plan);
        let cmd = config.build_command();
        assert!(cmd.contains("--permission-mode plan"));
    }

    #[test]
    fn test_shell_escape() {
        assert_eq!(shell_escape("hello"), "'hello'");
        assert_eq!(shell_escape("it's"), "'it'\"'\"'s'");
        assert_eq!(shell_escape("a'b'c"), "'a'\"'\"'b'\"'\"'c'");
    }
}
