//! Nagato socket listener.
//!
//! Receives Nagato command frames on `~/.unbound/nagato.sock`, delegates
//! command decisions to Itachi, and responds with daemon decision frames.

use crate::app::DaemonState;
use crate::itachi::ports::DecisionKind;
use crate::itachi::runtime::handle_remote_command_payload;
use std::path::PathBuf;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::oneshot;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

const TYPE_COMMAND: u8 = 0x01;
const TYPE_DAEMON_DECISION: u8 = 0x02;
const DECISION_ACK_MESSAGE: u8 = 0x01;
const DECISION_DO_NOT_ACK: u8 = 0x02;
const COMMAND_HEADER_SIZE: usize = 24;
const DECISION_HEADER_SIZE: usize = 24;
const LENGTH_PREFIX_SIZE: usize = 4;
const READ_BUF_SIZE: usize = 4096;

pub fn spawn_nagato_server(
    state: DaemonState,
    shutdown: oneshot::Receiver<()>,
) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        if let Err(err) = run_nagato_server(state, shutdown).await {
            error!(error = %err, "Nagato server stopped with error");
        }
    })
}

async fn run_nagato_server(
    state: DaemonState,
    mut shutdown: oneshot::Receiver<()>,
) -> Result<(), String> {
    let socket_path = state.paths.nagato_socket_file();
    cleanup_stale_socket(&socket_path)?;

    let listener = UnixListener::bind(&socket_path).map_err(|err| {
        format!(
            "failed to bind nagato socket {}: {err}",
            socket_path.display()
        )
    })?;
    info!(socket = %socket_path.display(), "Nagato server listening");

    loop {
        tokio::select! {
            _ = &mut shutdown => {
                info!("Nagato server shutdown requested");
                break;
            }
            accept_result = listener.accept() => {
                let (stream, _) = match accept_result {
                    Ok(v) => v,
                    Err(err) => {
                        warn!(error = %err, "Nagato accept failed");
                        continue;
                    }
                };

                let state_for_conn = state.clone();
                tokio::spawn(async move {
                    if let Err(err) = handle_connection(state_for_conn, stream).await {
                        warn!(error = %err, "Nagato connection closed with error");
                    }
                });
            }
        }
    }

    if let Err(err) = tokio::fs::remove_file(&socket_path).await {
        if err.kind() != std::io::ErrorKind::NotFound {
            warn!(
                socket = %socket_path.display(),
                error = %err,
                "Failed to remove Nagato socket on shutdown"
            );
        }
    }

    Ok(())
}

async fn handle_connection(state: DaemonState, mut stream: UnixStream) -> Result<(), String> {
    let mut buffer: Vec<u8> = Vec::with_capacity(READ_BUF_SIZE);
    let mut read_buf = [0u8; READ_BUF_SIZE];

    loop {
        let read = stream
            .read(&mut read_buf)
            .await
            .map_err(|err| format!("read error: {err}"))?;
        if read == 0 {
            return Ok(());
        }

        buffer.extend_from_slice(&read_buf[..read]);
        loop {
            let Some((frame_data, consumed)) = read_frame(&buffer)? else {
                break;
            };
            buffer.drain(..consumed);

            let command = match parse_command_frame(&frame_data) {
                Ok(frame) => frame,
                Err(err) => {
                    warn!(error = %err, "Invalid Nagato command frame");
                    continue;
                }
            };

            let decision = handle_remote_command_payload(state.clone(), &command.payload).await;
            let decision_byte = match decision.decision {
                DecisionKind::AckMessage => DECISION_ACK_MESSAGE,
                DecisionKind::DoNotAck => DECISION_DO_NOT_ACK,
            };
            let reply =
                encode_decision_frame(command.command_id, decision_byte, &decision.result_json);

            stream
                .write_all(&reply)
                .await
                .map_err(|err| format!("write decision failed: {err}"))?;
            debug!(
                command_id = %command.command_id,
                decision = decision_byte,
                "Sent daemon decision to Nagato"
            );
        }
    }
}

fn cleanup_stale_socket(path: &PathBuf) -> Result<(), String> {
    if !path.exists() {
        return Ok(());
    }
    std::fs::remove_file(path).map_err(|err| {
        format!(
            "failed to remove stale nagato socket {}: {err}",
            path.display()
        )
    })
}

fn read_frame(buf: &[u8]) -> Result<Option<(Vec<u8>, usize)>, String> {
    if buf.len() < LENGTH_PREFIX_SIZE {
        return Ok(None);
    }
    let frame_len = u32::from_le_bytes([buf[0], buf[1], buf[2], buf[3]]) as usize;
    let total_len = LENGTH_PREFIX_SIZE + frame_len;
    if buf.len() < total_len {
        return Ok(None);
    }
    Ok(Some((
        buf[LENGTH_PREFIX_SIZE..total_len].to_vec(),
        total_len,
    )))
}

struct CommandFrame {
    command_id: Uuid,
    payload: Vec<u8>,
}

fn parse_command_frame(data: &[u8]) -> Result<CommandFrame, String> {
    if data.len() < COMMAND_HEADER_SIZE {
        return Err(format!(
            "frame too short: got {}, need at least {}",
            data.len(),
            COMMAND_HEADER_SIZE
        ));
    }

    if data[0] != TYPE_COMMAND {
        return Err(format!(
            "invalid frame type: expected 0x{:02x}, got 0x{:02x}",
            TYPE_COMMAND, data[0]
        ));
    }

    let command_id = Uuid::from_slice(&data[4..20])
        .map_err(|err| format!("invalid command_id UUID in frame: {err}"))?;
    let payload_len = u32::from_le_bytes([data[20], data[21], data[22], data[23]]) as usize;
    let expected_len = COMMAND_HEADER_SIZE + payload_len;
    if data.len() != expected_len {
        return Err(format!(
            "payload length mismatch: expected {}, got {}",
            expected_len,
            data.len()
        ));
    }

    Ok(CommandFrame {
        command_id,
        payload: data[24..].to_vec(),
    })
}

fn encode_decision_frame(command_id: Uuid, decision: u8, result: &[u8]) -> Vec<u8> {
    let result_len = result.len();
    let frame_len = DECISION_HEADER_SIZE + result_len;
    let mut out = Vec::with_capacity(LENGTH_PREFIX_SIZE + frame_len);

    out.extend_from_slice(&(frame_len as u32).to_le_bytes());
    out.push(TYPE_DAEMON_DECISION);
    out.push(decision);
    out.extend_from_slice(&[0, 0]); // reserved
    out.extend_from_slice(command_id.as_bytes());
    out.extend_from_slice(&(result_len as u32).to_le_bytes());
    out.extend_from_slice(result);
    out
}

#[cfg(test)]
mod tests {
    use super::{encode_decision_frame, parse_command_frame, read_frame, TYPE_COMMAND};
    use uuid::Uuid;

    #[test]
    fn read_frame_extracts_complete_payload() {
        let payload = b"abc";
        let mut data = Vec::new();
        data.extend_from_slice(&(payload.len() as u32).to_le_bytes());
        data.extend_from_slice(payload);

        let parsed = read_frame(&data).expect("read_frame should parse");
        let (frame, consumed) = parsed.expect("frame should be complete");
        assert_eq!(frame, payload);
        assert_eq!(consumed, data.len());
    }

    #[test]
    fn parse_command_frame_success() {
        let command_id = Uuid::new_v4();
        let payload = b"{\"type\":\"um.secret.request.v1\"}";
        let mut frame = Vec::new();
        frame.push(TYPE_COMMAND);
        frame.push(0);
        frame.extend_from_slice(&[0, 0]);
        frame.extend_from_slice(command_id.as_bytes());
        frame.extend_from_slice(&(payload.len() as u32).to_le_bytes());
        frame.extend_from_slice(payload);

        let parsed = parse_command_frame(&frame).expect("frame should parse");
        assert_eq!(parsed.command_id, command_id);
        assert_eq!(parsed.payload, payload);
    }

    #[test]
    fn encode_decision_frame_has_expected_type_and_ids() {
        let command_id = Uuid::new_v4();
        let payload = b"{\"status\":\"accepted\"}";
        let frame = encode_decision_frame(command_id, 0x01, payload);

        let frame_len = u32::from_le_bytes([frame[0], frame[1], frame[2], frame[3]]) as usize;
        assert_eq!(frame_len + 4, frame.len());
        assert_eq!(frame[4], 0x02);
        assert_eq!(frame[5], 0x01);

        let mut id_bytes = [0u8; 16];
        id_bytes.copy_from_slice(&frame[8..24]);
        assert_eq!(Uuid::from_bytes(id_bytes), command_id);
    }
}
