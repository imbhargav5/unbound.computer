//! Terminal process output streaming and event handling.

use crate::app::DaemonState;
use armin::{NewMessage, SessionId, SessionWriter};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Child;
use tokio::sync::broadcast;
use tracing::{debug, error, info, warn};

/// Handle terminal process output, storing events via Armin.
///
/// Terminal output is stored as JSON messages with format:
/// - `{"type": "terminal_output", "stream": "stdout"|"stderr", "content": "..."}`
/// - `{"type": "terminal_finished", "exit_code": N}`
pub async fn handle_terminal_process(
    mut child: Child,
    session_id: String,
    state: DaemonState,
    stop_tx: broadcast::Sender<()>,
) {
    info!(
        session_id = %session_id,
        "Starting to handle terminal process"
    );

    let mut stop_rx = stop_tx.subscribe();

    let armin_session_id = SessionId::from_string(&session_id);

    let stdout = match child.stdout.take() {
        Some(s) => s,
        None => {
            error!("Failed to get stdout from terminal process");
            return;
        }
    };

    let stderr = child.stderr.take();

    let mut stdout_reader = BufReader::new(stdout).lines();

    // Spawn stderr reader task
    let armin_for_stderr = state.armin.clone();
    let session_id_for_stderr = armin_session_id.clone();
    let stderr_task = if let Some(stderr) = stderr {
        Some(tokio::spawn(async move {
            let mut stderr_reader = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = stderr_reader.next_line().await {
                // Store stderr output as message
                let content = serde_json::json!({
                    "type": "terminal_output",
                    "stream": "stderr",
                    "content": line,
                })
                .to_string();

                if let Err(e) =
                    armin_for_stderr.append(&session_id_for_stderr, NewMessage { content })
                {
                    tracing::warn!(error = %e, "Failed to store terminal stderr output");
                }
            }
        }))
    } else {
        None
    };

    loop {
        tokio::select! {
            // Check for stop signal
            _ = stop_rx.recv() => {
                info!("Stop signal received - killing process");
                let _ = child.kill().await;
                break;
            }

            // Read next line from stdout
            line_result = stdout_reader.next_line() => {
                match line_result {
                    Ok(Some(line)) => {
                        // Store stdout output as message
                        let content = serde_json::json!({
                            "type": "terminal_output",
                            "stream": "stdout",
                            "content": line,
                        }).to_string();

                        if let Err(e) = state.armin.append(
                            &armin_session_id,
                            NewMessage { content },
                        ) {
                            warn!(error = %e, "Failed to store terminal stdout output");
                        }
                    }
                    Ok(None) => {
                        // EOF - process finished
                        debug!("Terminal stdout closed (EOF)");
                        break;
                    }
                    Err(e) => {
                        error!(error = %e, "Error reading terminal stdout");
                        break;
                    }
                }
            }
        }
    }

    // Wait for stderr task to complete
    if let Some(task) = stderr_task {
        let _ = task.await;
    }

    // Wait for process to finish and get exit code
    let exit_code = match child.wait().await {
        Ok(status) => {
            let code = status.code().unwrap_or(-1);
            if status.success() {
                info!(exit_code = code, "Terminal process finished successfully");
            } else {
                warn!(
                    exit_code = code,
                    "Terminal process exited with non-zero code"
                );
            }
            code
        }
        Err(e) => {
            error!(error = %e, "Error waiting for terminal process");
            -1
        }
    };

    // Store finished event
    let content = serde_json::json!({
        "type": "terminal_finished",
        "exit_code": exit_code,
    })
    .to_string();

    if let Err(e) = state
        .armin
        .append(&armin_session_id, NewMessage { content })
    {
        warn!(error = %e, "Failed to store terminal finished event");
    }

    // Remove from running processes
    {
        let mut processes = state.terminal_processes.lock().unwrap();
        processes.remove(&session_id);
        info!(session_id = %session_id, "Cleaned up terminal process");
    }
}
