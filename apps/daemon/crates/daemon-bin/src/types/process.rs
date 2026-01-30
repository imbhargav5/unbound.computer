//! Process tracking types for Claude and terminal processes.

use tokio::process::Child;
use tokio::sync::broadcast;

/// Tracks a running Claude process.
#[allow(dead_code)]
pub struct ClaudeProcess {
    pub child: Child,
    pub session_id: String,
    pub stop_tx: broadcast::Sender<()>,
}

/// Tracks a running terminal process.
#[allow(dead_code)]
pub struct TerminalProcess {
    pub child: Child,
    pub session_id: String,
    pub stop_tx: broadcast::Sender<()>,
}
