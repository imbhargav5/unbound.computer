//! Terminal process output streaming and event handling.

use crate::app::DaemonState;
use daemon_stream::{EventType as StreamEventType, StreamProducer};
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Child;
use tokio::sync::broadcast;
use tracing::{debug, error, info, warn};

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

    // Create shared memory stream producer for low-latency event delivery
    // We reuse existing producer if one exists (from Claude process), or create new
    let stream_producer: Option<Arc<StreamProducer>> = {
        let producers = state.stream_producers.lock().unwrap();
        if let Some(existing) = producers.get(&session_id) {
            Some(existing.clone())
        } else {
            drop(producers); // Release lock before creating new
            match StreamProducer::new(&session_id) {
                Ok(producer) => {
                    let producer = Arc::new(producer);
                    state
                        .stream_producers
                        .lock()
                        .unwrap()
                        .insert(session_id.clone(), producer.clone());
                    info!(
                        "\x1b[36m[TERMINAL]\x1b[0m Created shared memory stream for session: {}",
                        session_id
                    );
                    Some(producer)
                }
                Err(e) => {
                    error!(
                        "\x1b[31m[TERMINAL]\x1b[0m Failed to create shared memory stream: {}. Clients will not receive events.",
                        e
                    );
                    None
                }
            }
        }
    };

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
    let stream_producer_for_stderr = stream_producer.clone();
    let stderr_task = if let Some(stderr) = stderr {
        Some(tokio::spawn(async move {
            let mut stderr_reader = BufReader::new(stderr).lines();
            let mut seq = 10000i64; // Start stderr sequences higher to avoid collision
            while let Ok(Some(line)) = stderr_reader.next_line().await {
                seq += 1;

                // Write to shared memory for low-latency streaming
                if let Some(ref producer) = stream_producer_for_stderr {
                    let payload = serde_json::json!({
                        "stream": "stderr",
                        "content": line,
                    })
                    .to_string();
                    if let Err(e) =
                        producer.write_event(StreamEventType::TerminalOutput, seq, payload.as_bytes())
                    {
                        debug!(
                            "\x1b[33m[TERMINAL]\x1b[0m Shared memory write failed: {}",
                            e
                        );
                    }
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
                info!("\x1b[33m[TERMINAL]\x1b[0m Stop signal received - killing process");
                let _ = child.kill().await;
                break;
            }

            // Read next line from stdout
            line_result = stdout_reader.next_line() => {
                match line_result {
                    Ok(Some(line)) => {
                        sequence += 1;

                        // Write to shared memory for low-latency streaming
                        if let Some(ref producer) = stream_producer {
                            let payload = serde_json::json!({
                                "stream": "stdout",
                                "content": line,
                            }).to_string();
                            if let Err(e) = producer.write_event(
                                StreamEventType::TerminalOutput,
                                sequence,
                                payload.as_bytes(),
                            ) {
                                debug!(
                                    "\x1b[33m[TERMINAL]\x1b[0m Shared memory write failed: {}",
                                    e
                                );
                            }
                        }
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

    // Write finished event to shared memory
    if let Some(ref producer) = stream_producer {
        // Include exit code as JSON for consistency
        let payload = serde_json::json!({
            "exit_code": exit_code,
        })
        .to_string();
        if let Err(e) = producer.write_event(
            StreamEventType::TerminalFinished,
            sequence + 1,
            payload.as_bytes(),
        ) {
            debug!(
                "\x1b[33m[TERMINAL]\x1b[0m Shared memory write failed for finished event: {}",
                e
            );
        }
    }

    // Remove from running processes
    {
        let mut processes = state.terminal_processes.lock().unwrap();
        processes.remove(&session_id);
        info!(
            "\x1b[36m[TERMINAL]\x1b[0m Cleaned up terminal process for session: {}",
            session_id
        );
    }

    // Cleanup shared memory stream producer if no Claude process is using it
    if stream_producer.is_some() {
        let claude_running = state
            .claude_processes
            .lock()
            .unwrap()
            .contains_key(&session_id);

        if !claude_running {
            let mut producers = state.stream_producers.lock().unwrap();
            if let Some(producer) = producers.remove(&session_id) {
                producer.shutdown();
                info!(
                    "\x1b[36m[TERMINAL]\x1b[0m Cleaned up shared memory stream for session: {}",
                    session_id
                );
            }
        } else {
            debug!(
                "\x1b[36m[TERMINAL]\x1b[0m Keeping shared memory stream (Claude still running) for session: {}",
                session_id
            );
        }
    }
}
