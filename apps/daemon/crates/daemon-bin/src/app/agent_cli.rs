use claude_process_manager::DEFAULT_ALLOWED_TOOLS;
use serde_json::Value;
use std::env;
use std::path::Path;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader, Lines};
use tokio::process::{Child, ChildStderr, ChildStdout, Command};
use tokio::sync::broadcast;
use tokio::time::{timeout, Duration};
use tracing::{debug, info, warn};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentCliKind {
    Claude,
    Codex,
}

#[derive(Debug, Clone)]
pub struct AgentCliConfig {
    pub kind: AgentCliKind,
    pub executable: String,
    pub system_prompt: Option<String>,
    pub message: String,
    pub working_dir: String,
    pub resume_session_id: Option<String>,
    pub model: Option<String>,
    pub thinking_effort: Option<String>,
    pub permission_mode: Option<String>,
    pub enable_chrome: bool,
    pub skip_permissions: bool,
    pub interrupt_grace_sec: Option<u64>,
    pub extra_args: Vec<String>,
    pub environment_variables: Vec<(String, String)>,
}

impl AgentCliConfig {
    pub fn new(
        kind: AgentCliKind,
        executable: impl Into<String>,
        message: impl Into<String>,
        working_dir: impl Into<String>,
    ) -> Self {
        Self {
            kind,
            executable: executable.into(),
            system_prompt: None,
            message: message.into(),
            working_dir: working_dir.into(),
            resume_session_id: None,
            model: None,
            thinking_effort: None,
            permission_mode: None,
            enable_chrome: false,
            skip_permissions: false,
            interrupt_grace_sec: None,
            extra_args: Vec::new(),
            environment_variables: Vec::new(),
        }
    }

    pub fn build_args(&self) -> Vec<String> {
        match self.kind {
            AgentCliKind::Claude => build_claude_args(self),
            AgentCliKind::Codex => build_codex_args(self),
        }
    }
}

#[derive(Debug, Clone)]
pub enum AgentCliEvent {
    Json {
        raw: String,
        json: Value,
    },
    Stderr {
        line: String,
    },
    Finished {
        success: bool,
        exit_code: Option<i32>,
    },
    Stopped,
}

impl AgentCliEvent {
    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::Finished { .. } | Self::Stopped)
    }
}

pub struct AgentCliProcess {
    stop_tx: broadcast::Sender<()>,
    stream: Option<AgentCliEventStream>,
}

impl AgentCliProcess {
    pub async fn spawn(config: AgentCliConfig) -> Result<Self, std::io::Error> {
        let args = config.build_args();

        info!(
            executable = %config.executable,
            working_dir = %config.working_dir,
            kind = ?config.kind,
            has_resume = config.resume_session_id.is_some(),
            "Spawning coding agent process"
        );
        debug!(args = ?args, "Agent CLI arguments");

        let mut command = Command::new(&config.executable);
        command
            .args(&args)
            .current_dir(&config.working_dir)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        for (key, value) in &config.environment_variables {
            command.env(key, value);
        }

        let child = command.spawn()?;
        let (stop_tx, stop_rx) = broadcast::channel::<()>(1);
        let stream = AgentCliEventStream::new(child, stop_rx, config.interrupt_grace_sec)?;

        Ok(Self {
            stop_tx,
            stream: Some(stream),
        })
    }

    pub fn take_stream(&mut self) -> Option<AgentCliEventStream> {
        self.stream.take()
    }

    pub fn stop_sender(&self) -> broadcast::Sender<()> {
        self.stop_tx.clone()
    }
}

pub struct AgentCliEventStream {
    stdout: Lines<BufReader<ChildStdout>>,
    stderr: Option<Lines<BufReader<ChildStderr>>>,
    child: Child,
    stop_rx: broadcast::Receiver<()>,
    interrupt_grace_sec: Option<u64>,
    finished: bool,
}

impl AgentCliEventStream {
    fn new(
        mut child: Child,
        stop_rx: broadcast::Receiver<()>,
        interrupt_grace_sec: Option<u64>,
    ) -> Result<Self, std::io::Error> {
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| std::io::Error::other("missing stdout for agent CLI process"))?;
        let stderr = child.stderr.take();

        Ok(Self {
            stdout: BufReader::new(stdout).lines(),
            stderr: stderr.map(|reader| BufReader::new(reader).lines()),
            child,
            stop_rx,
            interrupt_grace_sec,
            finished: false,
        })
    }

    pub async fn next(&mut self) -> Option<AgentCliEvent> {
        if self.finished {
            return None;
        }

        loop {
            tokio::select! {
                _ = self.stop_rx.recv() => {
                    debug!("Stop signal received - stopping coding agent process");
                    self.stop_process().await;
                    self.finished = true;
                    return Some(AgentCliEvent::Stopped);
                }
                line_result = self.stdout.next_line() => {
                    match line_result {
                        Ok(Some(line)) => {
                            if let Some(event) = parse_stdout_event(&line) {
                                return Some(event);
                            }
                        }
                        Ok(None) => return self.finish_process().await,
                        Err(error) => {
                            warn!(error = %error, "Error reading coding agent stdout");
                            return self.finish_process().await;
                        }
                    }
                }
                line_result = async {
                    if let Some(stderr) = &mut self.stderr {
                        stderr.next_line().await
                    } else {
                        Ok(None)
                    }
                }, if self.stderr.is_some() => {
                    match line_result {
                        Ok(Some(line)) => {
                            if !line.trim().is_empty() {
                                return Some(AgentCliEvent::Stderr { line });
                            }
                        }
                        Ok(None) => {
                            self.stderr = None;
                        }
                        Err(error) => {
                            warn!(error = %error, "Error reading coding agent stderr");
                            self.stderr = None;
                        }
                    }
                }
            }
        }
    }

    async fn finish_process(&mut self) -> Option<AgentCliEvent> {
        self.finished = true;

        match self.child.wait().await {
            Ok(status) => Some(AgentCliEvent::Finished {
                success: status.success(),
                exit_code: status.code(),
            }),
            Err(error) => {
                warn!(error = %error, "Error waiting for coding agent process");
                Some(AgentCliEvent::Finished {
                    success: false,
                    exit_code: None,
                })
            }
        }
    }

    async fn stop_process(&mut self) {
        #[cfg(unix)]
        if let Some(grace_sec) = self.interrupt_grace_sec {
            if grace_sec > 0 {
                if let Some(pid) = self.child.id() {
                    // Let the CLI flush and persist state before we force-kill it.
                    unsafe {
                        libc::kill(pid as i32, libc::SIGINT);
                    }
                    if timeout(Duration::from_secs(grace_sec), self.child.wait())
                        .await
                        .is_ok()
                    {
                        return;
                    }
                }
            }
        }

        let _ = self.child.kill().await;
        let _ = self.child.wait().await;
    }
}

pub fn detect_agent_cli_kind(command: Option<&str>, model: Option<&str>) -> AgentCliKind {
    let command = command.unwrap_or("claude");
    let model = model.unwrap_or_default();
    let command_name = std::path::Path::new(command)
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or(command)
        .to_ascii_lowercase();
    let model_name = model.to_ascii_lowercase();

    if command_name.contains("codex") || model_name.contains("codex") {
        AgentCliKind::Codex
    } else {
        AgentCliKind::Claude
    }
}

pub fn agent_cli_label(kind: AgentCliKind) -> &'static str {
    match kind {
        AgentCliKind::Claude => "Claude",
        AgentCliKind::Codex => "Codex",
    }
}

pub fn build_agent_cli_config_from_adapter(
    adapter_config: Option<&serde_json::Map<String, Value>>,
    system_prompt: Option<&str>,
    message: &str,
    working_dir: String,
    resume_session_id: Option<&str>,
) -> AgentCliConfig {
    let kind = detect_agent_cli_kind(
        adapter_config
            .and_then(|config| config.get("command"))
            .and_then(Value::as_str),
        adapter_config
            .and_then(|config| config.get("model"))
            .and_then(Value::as_str),
    );
    let default_command = match kind {
        AgentCliKind::Claude => "claude",
        AgentCliKind::Codex => "codex",
    };
    let executable = resolve_agent_cli_executable(
        kind,
        adapter_config
            .and_then(|config| config.get("command"))
            .and_then(Value::as_str),
        default_command,
    );

    let mut config = AgentCliConfig::new(kind, executable, message, working_dir);
    config.system_prompt = system_prompt.map(ToOwned::to_owned);
    config.resume_session_id = resume_session_id.map(ToOwned::to_owned);
    config.model = adapter_config
        .and_then(|config| config.get("model"))
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    config.thinking_effort = adapter_config
        .and_then(|config| {
            config
                .get("thinkingEffort")
                .or_else(|| config.get("reasoningEffort"))
        })
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    config.permission_mode = adapter_config
        .and_then(|config| config.get("permissionMode"))
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    config.enable_chrome = adapter_config
        .and_then(|config| config.get("enableChrome"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    config.skip_permissions = adapter_config
        .and_then(|config| config.get("skipPermissions"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    config.extra_args = adapter_config
        .and_then(|config| config.get("extraArgs"))
        .and_then(Value::as_array)
        .map(|entries| {
            entries
                .iter()
                .filter_map(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    config.environment_variables = parse_environment_variables(adapter_config.and_then(|config| {
        config
            .get("environmentVariables")
            .or_else(|| config.get("envVars"))
    }));
    config
}

fn build_claude_args(config: &AgentCliConfig) -> Vec<String> {
    let mut args = vec![
        "-p".to_string(),
        "--verbose".to_string(),
        "--output-format".to_string(),
        "stream-json".to_string(),
        "--allowedTools".to_string(),
        DEFAULT_ALLOWED_TOOLS.to_string(),
    ];

    if let Some(model) = normalize_model(config.model.as_deref()) {
        args.push("--model".to_string());
        args.push(model);
    }

    if let Some(effort) =
        normalize_thinking_effort_for_kind(AgentCliKind::Claude, config.thinking_effort.as_deref())
    {
        args.push("--effort".to_string());
        args.push(effort);
    }

    if normalize_optional_string(config.permission_mode.as_deref())
        .is_some_and(|mode| mode == "plan")
    {
        args.push("--permission-mode".to_string());
        args.push("plan".to_string());
    }

    if let Some(system_prompt) = normalize_optional_string(config.system_prompt.as_deref()) {
        args.push("--append-system-prompt".to_string());
        args.push(system_prompt);
    }

    if let Some(session_id) = normalize_optional_string(config.resume_session_id.as_deref()) {
        args.push("-r".to_string());
        args.push(session_id);
    }

    if config.enable_chrome {
        args.push("--chrome".to_string());
    }

    if config.skip_permissions {
        args.push("--dangerously-skip-permissions".to_string());
    }

    args.extend(config.extra_args.iter().cloned());
    args.push(config.message.clone());
    args
}

fn build_codex_args(config: &AgentCliConfig) -> Vec<String> {
    let mut args = vec!["exec".to_string()];
    let approval_policy = if config.skip_permissions {
        r#"approval_policy="never""#
    } else {
        r#"approval_policy="on-request""#
    };

    if let Some(session_id) = normalize_optional_string(config.resume_session_id.as_deref()) {
        args.push("resume".to_string());
        args.push("--json".to_string());
        args.push("--skip-git-repo-check".to_string());
        args.push("-c".to_string());
        args.push(approval_policy.to_string());
        args.push("-c".to_string());
        args.push(r#"sandbox_mode="workspace-write""#.to_string());

        if let Some(system_prompt) = normalize_optional_string(config.system_prompt.as_deref()) {
            push_string_config_override(&mut args, "developer_instructions", &system_prompt);
        }

        if let Some(model) = normalize_model(config.model.as_deref()) {
            args.push("-m".to_string());
            args.push(model);
        }

        if config.enable_chrome {
            args.push("--enable".to_string());
            args.push("web_search".to_string());
        }

        if let Some(effort) = normalize_thinking_effort_for_kind(
            AgentCliKind::Codex,
            config.thinking_effort.as_deref(),
        ) {
            args.push("-c".to_string());
            args.push(format!(r#"model_reasoning_effort="{effort}""#));
        }

        args.extend(config.extra_args.iter().cloned());
        args.push(session_id);
        args.push(config.message.clone());
        return args;
    }

    args.push("--json".to_string());
    args.push("--skip-git-repo-check".to_string());
    args.push("-c".to_string());
    args.push(approval_policy.to_string());
    args.push("-c".to_string());
    args.push(r#"sandbox_mode="workspace-write""#.to_string());

    if let Some(system_prompt) = normalize_optional_string(config.system_prompt.as_deref()) {
        push_string_config_override(&mut args, "developer_instructions", &system_prompt);
    }

    if let Some(model) = normalize_model(config.model.as_deref()) {
        args.push("-m".to_string());
        args.push(model);
    }

    if config.enable_chrome {
        args.push("--enable".to_string());
        args.push("web_search".to_string());
    }

    if let Some(effort) =
        normalize_thinking_effort_for_kind(AgentCliKind::Codex, config.thinking_effort.as_deref())
    {
        args.push("-c".to_string());
        args.push(format!(r#"model_reasoning_effort="{effort}""#));
    }

    args.extend(config.extra_args.iter().cloned());
    args.push(config.message.clone());
    args
}

fn normalize_optional_string(value: Option<&str>) -> Option<String> {
    let trimmed = value?.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn normalize_model(value: Option<&str>) -> Option<String> {
    let model = normalize_optional_string(value)?;
    if model.eq_ignore_ascii_case("default") {
        None
    } else {
        Some(model)
    }
}

fn resolve_agent_cli_executable(
    kind: AgentCliKind,
    configured_command: Option<&str>,
    default_command: &str,
) -> String {
    let Some(command) = normalize_optional_string(configured_command) else {
        return default_command.to_string();
    };

    if !looks_like_filesystem_path(&command) {
        return command;
    }

    let path = Path::new(&command);
    if path.exists() {
        return command;
    }

    if command_on_path(default_command) {
        warn!(
            configured_command = %command,
            fallback_command = default_command,
            kind = ?kind,
            "Configured agent CLI command path is missing; falling back to default command"
        );
        default_command.to_string()
    } else {
        warn!(
            configured_command = %command,
            kind = ?kind,
            "Configured agent CLI command path is missing and the default command was not found on PATH"
        );
        command
    }
}

fn looks_like_filesystem_path(value: &str) -> bool {
    let path = Path::new(value);
    path.is_absolute() || value.contains(std::path::MAIN_SEPARATOR) || value.contains('/')
}

fn command_on_path(command: &str) -> bool {
    let Some(path_value) = env::var_os("PATH") else {
        return false;
    };

    env::split_paths(&path_value).any(|directory| directory.join(command).exists())
}

fn push_string_config_override(args: &mut Vec<String>, key: &str, value: &str) {
    let serialized_value =
        serde_json::to_string(value).expect("serializing CLI config override should succeed");
    args.push("-c".to_string());
    args.push(format!("{key}={serialized_value}"));
}

fn normalize_thinking_effort_for_kind(kind: AgentCliKind, value: Option<&str>) -> Option<String> {
    let effort = normalize_optional_string(value)?;
    let normalized = effort.to_ascii_lowercase();

    match kind {
        AgentCliKind::Claude => {
            if normalized == "auto" {
                return None;
            }
            if normalized == "xhigh"
                || normalized == "extra high"
                || normalized == "extra_high"
                || normalized == "extrahigh"
            {
                return Some("max".to_string());
            }
            Some(normalized)
        }
        AgentCliKind::Codex => {
            if normalized == "auto" {
                return None;
            }
            if normalized == "max"
                || normalized == "extra high"
                || normalized == "extra_high"
                || normalized == "extrahigh"
            {
                return Some("xhigh".to_string());
            }
            Some(normalized)
        }
    }
}

fn parse_environment_variables(value: Option<&Value>) -> Vec<(String, String)> {
    value
        .and_then(Value::as_array)
        .map(|entries| {
            entries
                .iter()
                .filter_map(|entry| {
                    let key = entry.get("key").and_then(Value::as_str)?.trim().to_string();
                    if key.is_empty() {
                        return None;
                    }
                    let value = entry
                        .get("value")
                        .and_then(Value::as_str)
                        .unwrap_or_default()
                        .to_string();
                    Some((key, value))
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn parse_stdout_event(line: &str) -> Option<AgentCliEvent> {
    let trimmed = line.trim();
    if trimmed.is_empty() || !trimmed.starts_with('{') {
        return None;
    }

    match serde_json::from_str::<Value>(trimmed) {
        Ok(json) => Some(AgentCliEvent::Json {
            raw: trimmed.to_string(),
            json,
        }),
        Err(error) => {
            warn!(error = %error, "Failed to parse coding agent JSON event");
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn claude_args_include_selected_model_and_effort() {
        let mut config = AgentCliConfig::new(AgentCliKind::Claude, "claude", "hello", "/tmp");
        config.system_prompt = Some("Workspace type: worktree.".to_string());
        config.model = Some("claude-sonnet-4-6".to_string());
        config.thinking_effort = Some("high".to_string());
        config.resume_session_id = Some("sess-123".to_string());
        config.skip_permissions = true;
        config.enable_chrome = true;
        config.extra_args = vec!["--brief".to_string()];

        let args = config.build_args();

        assert!(args.iter().any(|arg| arg == "--model"));
        assert!(args.iter().any(|arg| arg == "claude-sonnet-4-6"));
        assert!(args.iter().any(|arg| arg == "--effort"));
        assert!(args.iter().any(|arg| arg == "high"));
        assert!(args.iter().any(|arg| arg == "--append-system-prompt"));
        assert!(args.iter().any(|arg| arg == "Workspace type: worktree."));
        assert!(args
            .iter()
            .any(|arg| arg == "--dangerously-skip-permissions"));
        assert!(args.iter().any(|arg| arg == "--chrome"));
        assert!(args.iter().any(|arg| arg == "--brief"));
        assert_eq!(args.last().map(String::as_str), Some("hello"));
    }

    #[test]
    fn codex_args_support_resume_and_reasoning_effort() {
        let mut config = AgentCliConfig::new(AgentCliKind::Codex, "codex", "continue", "/tmp");
        config.system_prompt = Some("Workspace type: repo root.".to_string());
        config.model = Some("gpt-5.3-codex".to_string());
        config.thinking_effort = Some("medium".to_string());
        config.resume_session_id = Some("thread-123".to_string());
        config.enable_chrome = true;

        let args = config.build_args();

        assert_eq!(args.first().map(String::as_str), Some("exec"));
        assert!(args.iter().any(|arg| arg == "resume"));
        assert!(args.iter().any(|arg| arg == "--json"));
        assert!(args.iter().any(|arg| arg == "--skip-git-repo-check"));
        assert!(args
            .iter()
            .any(|arg| arg == r#"approval_policy="on-request""#));
        assert!(args
            .iter()
            .any(|arg| arg == r#"sandbox_mode="workspace-write""#));
        assert!(args
            .iter()
            .any(|arg| arg == r#"developer_instructions="Workspace type: repo root.""#));
        assert!(args.iter().any(|arg| arg == "web_search"));
        assert!(args.iter().any(|arg| arg == "gpt-5.3-codex"));
        assert!(args
            .iter()
            .any(|arg| arg == r#"model_reasoning_effort="medium""#));
        assert_eq!(
            args.get(args.len() - 2).map(String::as_str),
            Some("thread-123")
        );
        assert_eq!(args.last().map(String::as_str), Some("continue"));
    }

    #[test]
    fn claude_args_map_xhigh_to_max_effort() {
        let mut config = AgentCliConfig::new(AgentCliKind::Claude, "claude", "hello", "/tmp");
        config.thinking_effort = Some("xhigh".to_string());

        let args = config.build_args();

        assert!(args.iter().any(|arg| arg == "--effort"));
        assert!(args.iter().any(|arg| arg == "max"));
    }

    #[test]
    fn codex_args_map_max_to_xhigh_effort() {
        let mut config = AgentCliConfig::new(AgentCliKind::Codex, "codex", "hello", "/tmp");
        config.thinking_effort = Some("max".to_string());

        let args = config.build_args();

        assert!(args
            .iter()
            .any(|arg| arg == r#"model_reasoning_effort="xhigh""#));
    }

    #[test]
    fn build_config_detects_reasoning_effort_alias() {
        let adapter = serde_json::json!({
            "command": "codex",
            "model": "gpt-5.3-codex",
            "reasoningEffort": "high",
            "skipPermissions": true,
        });

        let config = build_agent_cli_config_from_adapter(
            adapter.as_object(),
            Some("Workspace type: worktree."),
            "hello",
            "/tmp".to_string(),
            None,
        );

        assert_eq!(config.kind, AgentCliKind::Codex);
        assert_eq!(
            config.system_prompt.as_deref(),
            Some("Workspace type: worktree.")
        );
        assert_eq!(config.thinking_effort.as_deref(), Some("high"));
        assert!(config.skip_permissions);
    }

    #[test]
    fn build_config_falls_back_from_missing_absolute_command_path() {
        let adapter = serde_json::json!({
            "command": "/definitely/missing/claude",
        });

        let config = build_agent_cli_config_from_adapter(
            adapter.as_object(),
            None,
            "hello",
            "/tmp".to_string(),
            None,
        );

        assert_eq!(config.kind, AgentCliKind::Claude);
        assert_eq!(config.executable, "claude");
    }

    #[test]
    fn stdout_parser_ignores_non_json_lines() {
        assert!(parse_stdout_event("").is_none());
        assert!(parse_stdout_event("hello").is_none());
        assert!(parse_stdout_event("  warning").is_none());
    }
}
