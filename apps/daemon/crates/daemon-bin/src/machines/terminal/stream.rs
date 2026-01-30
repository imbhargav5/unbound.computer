//! Terminal process output streaming and event handling.

use crate::app::DaemonState;
use daemon_ipc::{Event, EventType};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Child;
use tokio::sync::broadcast;
use tracing::{error, info, warn};

/// Handle terminal process output, broadcasting events to subscribers.
pub async fn handle_terminal_process(
    mut child: Child,
    session_id: String,
    state: DaemonState,
    stop_tx: broadcast::Sender<()>,
) {
    info!(
        "\x1b[36m[TERMINAL]\x1b[0m Starting to handle terminal process for session: {}",
        session_id
    );

    let mut stop_rx = stop_tx.subscribe();

    let stdout = match child.stdout.take() {
        Some(s) => s,
        None => {
            error!("\x1b[31m[TERMINAL]\x1b[0m Failed to get stdout from terminal process");
            return;
        }
    };

    let stderr = child.stderr.take();

    let mut stdout_reader = BufReader::new(stdout).lines();
    let mut sequence = 0i64;

    // Spawn stderr reader task
    let state_for_stderr = state.clone();
    let session_id_for_stderr = session_id.clone();
    let stderr_task = if let Some(stderr) = stderr {
        Some(tokio::spawn(async move {
            let mut stderr_reader = BufReader::new(stderr).lines();
            let mut seq = 10000i64; // Start stderr sequences higher to avoid collision
            while let Ok(Some(line)) = stderr_reader.next_line().await {
                seq += 1;
                let event = Event::new(
                    EventType::TerminalOutput,
                    &session_id_for_stderr,
                    serde_json::json!({
                        "stream": "stderr",
                        "content": line,
                    }),
                    seq,
                );
                state_for_stderr
                    .subscriptions
                    .broadcast_or_create(&session_id_for_stderr, event)
                    .await;
            }
        }))
    } else {
        None
    };

    loop {
        tokio::select! {
            // Check for stop signal
            _ = stop_rx.recv() => {
                info!("\x1b[33m[TERMINAL]\x1b[0m Stop signal received - killing process");
                let _ = child.kill().await;
                break;
            }

            // Read next line from stdout
            line_result = stdout_reader.next_line() => {
                match line_result {
                    Ok(Some(line)) => {
                        sequence += 1;
                        let event = Event::new(
                            EventType::TerminalOutput,
                            &session_id,
                            serde_json::json!({
                                "stream": "stdout",
                                "content": line,
                            }),
                            sequence,
                        );
                        state.subscriptions.broadcast_or_create(&session_id, event).await;
                    }
                    Ok(None) => {
                        // EOF - process finished
                        info!("\x1b[36m[TERMINAL]\x1b[0m Terminal stdout closed (EOF)");
                        break;
                    }
                    Err(e) => {
                        error!("\x1b[31m[TERMINAL]\x1b[0m Error reading terminal stdout: {}", e);
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
                info!(
                    "\x1b[32m[TERMINAL]\x1b[0m Terminal process finished successfully (exit code: {})",
                    code
                );
            } else {
                warn!(
                    "\x1b[33m[TERMINAL]\x1b[0m Terminal process exited with code: {}",
                    code
                );
            }
            code
        }
        Err(e) => {
            error!(
                "\x1b[31m[TERMINAL]\x1b[0m Error waiting for terminal process: {}",
                e
            );
            -1
        }
    };

    // Broadcast finished event
    let finished_event = Event::new(
        EventType::TerminalFinished,
        &session_id,
        serde_json::json!({
            "exit_code": exit_code,
        }),
        sequence + 1,
    );
    state
        .subscriptions
        .broadcast_or_create(&session_id, finished_event)
        .await;

    // Remove from running processes
    {
        let mut processes = state.terminal_processes.lock().unwrap();
        processes.remove(&session_id);
        info!(
            "\x1b[36m[TERMINAL]\x1b[0m Cleaned up terminal process for session: {}",
            session_id
        );
    }
}
