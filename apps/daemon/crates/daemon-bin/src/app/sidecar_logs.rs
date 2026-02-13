//! Sidecar stdout/stderr capture and lifecycle helpers.

use crate::app::DaemonState;
use std::io::{BufRead, BufReader};
use std::process::Child;
use std::thread::{self, JoinHandle};
use tracing::{debug, warn};

pub type SidecarLogTask = JoinHandle<()>;

/// Attach stdout/stderr line readers for a sidecar process.
///
/// Readers run on background threads and emit structured tracing events.
pub fn attach_sidecar_log_streams(
    child: &mut Child,
    sidecar_name: &'static str,
    source: &'static str,
) -> Vec<SidecarLogTask> {
    let mut tasks = Vec::new();

    if let Some(stdout) = child.stdout.take() {
        tasks.push(spawn_reader(stdout, sidecar_name, source, "stdout"));
    } else {
        debug!(
            sidecar_name = sidecar_name,
            source = source,
            stream = "stdout",
            "Sidecar stdout stream unavailable for capture"
        );
    }

    if let Some(stderr) = child.stderr.take() {
        tasks.push(spawn_reader(stderr, sidecar_name, source, "stderr"));
    } else {
        debug!(
            sidecar_name = sidecar_name,
            source = source,
            stream = "stderr",
            "Sidecar stderr stream unavailable for capture"
        );
    }

    tasks
}

/// Register sidecar log tasks on daemon shared state.
pub fn register_sidecar_log_tasks(
    state: &DaemonState,
    sidecar_name: &str,
    tasks: Vec<SidecarLogTask>,
) {
    if tasks.is_empty() {
        return;
    }

    let mut guard = state.sidecar_log_tasks.lock().unwrap();
    guard
        .entry(sidecar_name.to_string())
        .or_insert_with(Vec::new)
        .extend(tasks);
}

/// Replace sidecar log tasks for a sidecar name, joining prior tasks.
pub fn replace_sidecar_log_tasks(
    state: &DaemonState,
    sidecar_name: &str,
    tasks: Vec<SidecarLogTask>,
) {
    let stale_tasks = {
        let mut guard = state.sidecar_log_tasks.lock().unwrap();
        let stale = guard.remove(sidecar_name).unwrap_or_default();
        if !tasks.is_empty() {
            guard.insert(sidecar_name.to_string(), tasks);
        }
        stale
    };
    join_tasks(stale_tasks);
}

/// Reap and join all sidecar log tasks for a sidecar process name.
pub fn reap_sidecar_log_tasks(state: &DaemonState, sidecar_name: &str) {
    let tasks = {
        let mut guard = state.sidecar_log_tasks.lock().unwrap();
        guard.remove(sidecar_name).unwrap_or_default()
    };
    join_tasks(tasks);
}

/// Reap and join all sidecar log tasks for all sidecars.
pub fn reap_all_sidecar_log_tasks(state: &DaemonState) {
    let all = {
        let mut guard = state.sidecar_log_tasks.lock().unwrap();
        std::mem::take(&mut *guard)
    };
    for (_, tasks) in all {
        join_tasks(tasks);
    }
}

fn spawn_reader(
    stream: impl std::io::Read + Send + 'static,
    sidecar_name: &'static str,
    source: &'static str,
    stream_name: &'static str,
) -> SidecarLogTask {
    thread::spawn(move || {
        let mut reader = BufReader::new(stream);
        let mut line = String::new();

        loop {
            line.clear();
            match reader.read_line(&mut line) {
                Ok(0) => break, // EOF
                Ok(_) => {
                    let trimmed = line.trim_end_matches(['\r', '\n']).to_string();
                    if trimmed.is_empty() {
                        continue;
                    }

                    tracing::info!(
                        runtime = "sidecar",
                        component = %format!("sidecar.{}", sidecar_name),
                        event_code = "daemon.sidecar.log_line",
                        sidecar_name = sidecar_name,
                        sidecar_source = source,
                        stream = stream_name,
                        line = %trimmed,
                        "sidecar log line"
                    );
                }
                Err(err) => {
                    warn!(
                        runtime = "sidecar",
                        component = %format!("sidecar.{}", sidecar_name),
                        event_code = "daemon.sidecar.stream_read_failed",
                        sidecar_name = sidecar_name,
                        sidecar_source = source,
                        stream = stream_name,
                        error = %err,
                        "sidecar log stream read failed"
                    );
                    break;
                }
            }
        }

        debug!(
            component = %format!("sidecar.{}", sidecar_name),
            event_code = "daemon.sidecar.stream_ended",
            sidecar_name = sidecar_name,
            sidecar_source = source,
            stream = stream_name,
            "sidecar log stream ended"
        );
    })
}

fn join_tasks(tasks: Vec<SidecarLogTask>) {
    for task in tasks {
        if let Err(err) = task.join() {
            warn!(
                runtime = "sidecar",
                component = "sidecar.supervisor",
                event_code = "daemon.sidecar.task_join_failed",
                error = ?err,
                "Failed joining sidecar log task"
            );
        }
    }
}
