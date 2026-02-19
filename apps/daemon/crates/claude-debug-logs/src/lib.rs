use chrono::{Local, NaiveDate, SecondsFormat, Utc};
use daemon_config_and_utils::Paths;
use serde::Serialize;
use std::fs::OpenOptions;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

const ENV_ENABLED: &str = "UNBOUND_CLAUDE_DEBUG_LOGS_ENABLED";
const ENV_DIR: &str = "UNBOUND_CLAUDE_DEBUG_LOGS_DIR";
const OBS_MODE_ENV: &str = "UNBOUND_OBS_MODE";

const EVENT_CODE: &str = "daemon.claude.raw";
const OBS_PREFIX: &str = "claude.raw";

#[derive(Debug)]
pub struct ClaudeDebugLogs {
    enabled: bool,
    base_dir: PathBuf,
    write_lock: Mutex<()>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ClaudeRawLogEntry {
    pub timestamp: String,
    pub event_code: String,
    pub obs_prefix: String,
    pub session_id: String,
    pub sequence: i64,
    pub claude_type: String,
    pub raw_json: String,
}

impl ClaudeDebugLogs {
    pub fn from_env() -> Self {
        Self {
            enabled: read_enabled_from_env(),
            base_dir: read_base_dir_from_env(),
            write_lock: Mutex::new(()),
        }
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    pub fn base_dir(&self) -> &Path {
        &self.base_dir
    }

    pub fn record_raw_event(
        &self,
        session_id: &str,
        sequence: i64,
        raw_json: &str,
    ) -> io::Result<Option<PathBuf>> {
        if !self.enabled {
            return Ok(None);
        }

        let claude_type = Self::extract_claude_type(raw_json);
        let entry = ClaudeRawLogEntry {
            timestamp: Utc::now().to_rfc3339_opts(SecondsFormat::Micros, true),
            event_code: EVENT_CODE.to_string(),
            obs_prefix: OBS_PREFIX.to_string(),
            session_id: session_id.to_string(),
            sequence,
            claude_type,
            raw_json: raw_json.to_string(),
        };

        let file_path = self.file_path_for_session(session_id, Local::now().date_naive());
        let serialized = serde_json::to_string(&entry).map_err(io::Error::other)?;

        let _guard = self
            .write_lock
            .lock()
            .expect("claude debug logs mutex poisoned");

        if let Some(parent) = file_path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&file_path)?;
        writeln!(file, "{serialized}")?;

        Ok(Some(file_path))
    }

    pub fn extract_claude_type(raw_json: &str) -> String {
        serde_json::from_str::<serde_json::Value>(raw_json)
            .ok()
            .and_then(|json| json.get("type").and_then(|v| v.as_str()).map(str::to_owned))
            .map(|value| value.to_ascii_lowercase())
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| "unknown".to_string())
    }

    fn file_path_for_session(&self, session_id: &str, date: NaiveDate) -> PathBuf {
        self.base_dir
            .join(Self::dated_session_filename(session_id, date))
    }

    fn dated_session_filename(session_id: &str, date: NaiveDate) -> String {
        let sanitized = sanitize_session_id(session_id);
        format!("{}_{}.jsonl", date.format("%Y-%m-%d"), sanitized)
    }
}

fn read_enabled_from_env() -> bool {
    if let Some(explicit) = std::env::var(ENV_ENABLED)
        .ok()
        .and_then(|raw| parse_bool(raw.as_str()))
    {
        return explicit;
    }

    !matches!(
        std::env::var(OBS_MODE_ENV)
            .ok()
            .map(|value| value.trim().to_ascii_lowercase())
            .as_deref(),
        Some("prod") | Some("production")
    )
}

fn read_base_dir_from_env() -> PathBuf {
    if let Some(path) = std::env::var(ENV_DIR)
        .ok()
        .map(|raw| raw.trim().to_string())
        .filter(|raw| !raw.is_empty())
    {
        return PathBuf::from(path);
    }

    Paths::new()
        .map(|paths| paths.logs_dir().join("claude-debug-logs"))
        .unwrap_or_else(|_| PathBuf::from(".unbound/logs/claude-debug-logs"))
}

fn sanitize_session_id(session_id: &str) -> String {
    let mut out = String::with_capacity(session_id.len());

    for ch in session_id.chars() {
        if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
            out.push(ch);
        } else {
            out.push('_');
        }
    }

    if out.is_empty() {
        "unknown-session".to_string()
    } else {
        out
    }
}

fn parse_bool(raw: &str) -> Option<bool> {
    match raw.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn extracts_claude_type_from_json() {
        let raw = r#"{"type":"assistant","message":{"content":[]}}"#;
        assert_eq!(ClaudeDebugLogs::extract_claude_type(raw), "assistant");
    }

    #[test]
    fn unknown_type_for_invalid_json() {
        assert_eq!(ClaudeDebugLogs::extract_claude_type("{"), "unknown");
    }

    #[test]
    fn filename_has_date_then_session_id() {
        let date = NaiveDate::from_ymd_opt(2026, 2, 19).unwrap();
        let filename = ClaudeDebugLogs::dated_session_filename("abc-123", date);
        assert_eq!(filename, "2026-02-19_abc-123.jsonl");
    }

    #[test]
    fn filename_sanitizes_path_chars() {
        let date = NaiveDate::from_ymd_opt(2026, 2, 19).unwrap();
        let filename = ClaudeDebugLogs::dated_session_filename("../../bad/session", date);
        assert_eq!(filename, "2026-02-19_______bad_session.jsonl");
    }

    #[test]
    fn writes_one_jsonl_line_to_dated_session_file() {
        let dir = TempDir::new().unwrap();
        let logger = ClaudeDebugLogs {
            enabled: true,
            base_dir: dir.path().to_path_buf(),
            write_lock: Mutex::new(()),
        };

        let path = logger
            .record_raw_event("session-42", 7, r#"{"type":"result","is_error":false}"#)
            .unwrap()
            .unwrap();
        assert!(path.exists());

        let content = std::fs::read_to_string(path).unwrap();
        let mut lines = content.lines();
        let line = lines.next().unwrap();
        assert!(lines.next().is_none());

        let json: serde_json::Value = serde_json::from_str(line).unwrap();
        assert_eq!(json["session_id"], "session-42");
        assert_eq!(json["sequence"], 7);
        assert_eq!(json["claude_type"], "result");
        assert_eq!(json["event_code"], EVENT_CODE);
        assert_eq!(json["obs_prefix"], OBS_PREFIX);
    }

    #[test]
    fn disabled_mode_skips_file_write() {
        let dir = TempDir::new().unwrap();
        let logger = ClaudeDebugLogs {
            enabled: false,
            base_dir: dir.path().to_path_buf(),
            write_lock: Mutex::new(()),
        };

        let path = logger
            .record_raw_event("session-42", 7, r#"{"type":"assistant"}"#)
            .unwrap();
        assert!(path.is_none());
        assert!(std::fs::read_dir(dir.path()).unwrap().next().is_none());
    }
}
