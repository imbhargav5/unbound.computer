//! Claude CLI events.

/// An event emitted by the Claude CLI process.
#[derive(Debug, Clone)]
pub enum ClaudeEvent {
    /// A JSON event was received from Claude's stdout.
    Json {
        /// The event type (e.g., "system", "assistant", "user", "result").
        event_type: String,
        /// The raw JSON string.
        raw: String,
        /// The parsed JSON value.
        json: serde_json::Value,
    },

    /// A system event with a Claude session ID.
    SystemWithSessionId {
        /// The Claude session ID.
        claude_session_id: String,
        /// The raw JSON string.
        raw: String,
    },

    /// A result event indicating completion.
    Result {
        /// Whether the result indicates an error.
        is_error: bool,
        /// The raw JSON string.
        raw: String,
    },

    /// Stderr output from the process.
    Stderr {
        /// The stderr line.
        line: String,
    },

    /// The process has finished.
    Finished {
        /// Whether the process exited successfully.
        success: bool,
        /// Exit code if available.
        exit_code: Option<i32>,
    },

    /// The process was stopped via signal.
    Stopped,
}

impl ClaudeEvent {
    /// Create a JSON event from parsed data.
    pub(crate) fn from_json(raw: String, json: serde_json::Value) -> Self {
        let event_type = json
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or("unknown")
            .to_string();

        // Check for special event types
        if event_type == "system" {
            if let Some(session_id) = json.get("session_id").and_then(|v| v.as_str()) {
                return Self::SystemWithSessionId {
                    claude_session_id: session_id.to_string(),
                    raw,
                };
            }
        }

        if event_type == "result" {
            let is_error = json
                .get("is_error")
                .and_then(|v| v.as_bool())
                .unwrap_or(false);
            return Self::Result { is_error, raw };
        }

        Self::Json {
            event_type,
            raw,
            json,
        }
    }

    /// Get the event type string.
    pub fn event_type(&self) -> &str {
        match self {
            Self::Json { event_type, .. } => event_type,
            Self::SystemWithSessionId { .. } => "system",
            Self::Result { .. } => "result",
            Self::Stderr { .. } => "stderr",
            Self::Finished { .. } => "finished",
            Self::Stopped => "stopped",
        }
    }

    /// Get the raw JSON if this is a JSON event.
    pub fn raw_json(&self) -> Option<&str> {
        match self {
            Self::Json { raw, .. } => Some(raw),
            Self::SystemWithSessionId { raw, .. } => Some(raw),
            Self::Result { raw, .. } => Some(raw),
            _ => None,
        }
    }

    /// Check if this is a terminal event (process finished or stopped).
    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::Finished { .. } | Self::Stopped)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_from_json_basic() {
        let json = serde_json::json!({
            "type": "assistant",
            "content": "Hello"
        });
        let event = ClaudeEvent::from_json(json.to_string(), json);

        assert_eq!(event.event_type(), "assistant");
        assert!(event.raw_json().is_some());
    }

    #[test]
    fn test_from_json_system_with_session() {
        let json = serde_json::json!({
            "type": "system",
            "session_id": "claude-sess-123"
        });
        let event = ClaudeEvent::from_json(json.to_string(), json);

        match event {
            ClaudeEvent::SystemWithSessionId {
                claude_session_id, ..
            } => {
                assert_eq!(claude_session_id, "claude-sess-123");
            }
            _ => panic!("Expected SystemWithSessionId"),
        }
    }

    #[test]
    fn test_from_json_result() {
        let json = serde_json::json!({
            "type": "result",
            "is_error": false
        });
        let event = ClaudeEvent::from_json(json.to_string(), json);

        match event {
            ClaudeEvent::Result { is_error, .. } => {
                assert!(!is_error);
            }
            _ => panic!("Expected Result"),
        }
    }

    #[test]
    fn test_is_terminal() {
        assert!(ClaudeEvent::Finished {
            success: true,
            exit_code: Some(0)
        }
        .is_terminal());
        assert!(ClaudeEvent::Stopped.is_terminal());
        assert!(!ClaudeEvent::Json {
            event_type: "test".to_string(),
            raw: "{}".to_string(),
            json: serde_json::Value::Null
        }
        .is_terminal());
    }
}
