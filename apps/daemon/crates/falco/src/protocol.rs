//! Binary framing protocol for Falco-Daemon communication.
//!
//! All frames use little-endian byte order.

use crate::error::{FalcoError, FalcoResult};
use uuid::Uuid;

/// Frame type identifier for CommandFrame.
pub const FRAME_TYPE_COMMAND: u8 = 0x01;

/// Frame type identifier for DaemonDecisionFrame.
pub const FRAME_TYPE_DECISION: u8 = 0x02;

/// Daemon decision: ACK the Redis message.
pub const DECISION_ACK_REDIS: u8 = 0x01;

/// Daemon decision: Do not ACK the Redis message.
pub const DECISION_DO_NOT_ACK: u8 = 0x02;

/// Decision from the daemon about how to handle a command.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    /// ACK the message in Redis (remove from PEL).
    AckRedis,
    /// Do not ACK the message (leave in PEL for redelivery).
    DoNotAck,
}

impl Decision {
    /// Convert from wire format byte.
    pub fn from_byte(byte: u8) -> FalcoResult<Self> {
        match byte {
            DECISION_ACK_REDIS => Ok(Decision::AckRedis),
            DECISION_DO_NOT_ACK => Ok(Decision::DoNotAck),
            other => Err(FalcoError::Protocol(format!("Unknown decision byte: {:#04x}", other))),
        }
    }

    /// Convert to wire format byte.
    pub fn to_byte(self) -> u8 {
        match self {
            Decision::AckRedis => DECISION_ACK_REDIS,
            Decision::DoNotAck => DECISION_DO_NOT_ACK,
        }
    }
}

/// Command frame sent from Falco to the daemon.
///
/// Wire format:
/// ```text
/// [4: total_len][1: type=0x01][1: flags][2: reserved][16: command_id][4: payload_len][N: payload]
/// ```
#[derive(Debug, Clone)]
pub struct CommandFrame {
    /// Unique identifier for this command (for correlation).
    pub command_id: Uuid,
    /// Flags (reserved for future use).
    pub flags: u8,
    /// The encrypted command payload (opaque to Falco).
    pub encrypted_payload: Vec<u8>,
}

impl CommandFrame {
    /// Header size in bytes (type + flags + reserved + command_id + payload_len).
    const HEADER_SIZE: usize = 1 + 1 + 2 + 16 + 4;

    /// Create a new CommandFrame.
    pub fn new(command_id: Uuid, encrypted_payload: Vec<u8>) -> Self {
        Self {
            command_id,
            flags: 0,
            encrypted_payload,
        }
    }

    /// Encode the frame to bytes (including length prefix).
    pub fn encode(&self) -> Vec<u8> {
        let payload_len = self.encrypted_payload.len();
        let total_len = Self::HEADER_SIZE + payload_len;

        let mut buf = Vec::with_capacity(4 + total_len);

        // Length prefix (excludes itself)
        buf.extend_from_slice(&(total_len as u32).to_le_bytes());

        // Frame type
        buf.push(FRAME_TYPE_COMMAND);

        // Flags
        buf.push(self.flags);

        // Reserved (2 bytes)
        buf.extend_from_slice(&[0u8, 0u8]);

        // Command ID (16 bytes)
        buf.extend_from_slice(self.command_id.as_bytes());

        // Payload length
        buf.extend_from_slice(&(payload_len as u32).to_le_bytes());

        // Payload
        buf.extend_from_slice(&self.encrypted_payload);

        buf
    }

    /// Decode a CommandFrame from bytes (excluding length prefix).
    ///
    /// The caller should first read the 4-byte length prefix, then read
    /// that many bytes and pass them to this function.
    pub fn decode(data: &[u8]) -> FalcoResult<Self> {
        if data.len() < Self::HEADER_SIZE {
            return Err(FalcoError::Protocol(format!(
                "CommandFrame too short: {} bytes, need at least {}",
                data.len(),
                Self::HEADER_SIZE
            )));
        }

        // Frame type
        if data[0] != FRAME_TYPE_COMMAND {
            return Err(FalcoError::Protocol(format!(
                "Expected CommandFrame type {:#04x}, got {:#04x}",
                FRAME_TYPE_COMMAND, data[0]
            )));
        }

        // Flags
        let flags = data[1];

        // Reserved bytes at [2..4] are ignored

        // Command ID
        let command_id_bytes: [u8; 16] = data[4..20]
            .try_into()
            .map_err(|_| FalcoError::Protocol("Invalid command_id length".to_string()))?;
        let command_id = Uuid::from_bytes(command_id_bytes);

        // Payload length
        let payload_len = u32::from_le_bytes(
            data[20..24]
                .try_into()
                .map_err(|_| FalcoError::Protocol("Invalid payload_len".to_string()))?,
        ) as usize;

        // Validate payload length
        let expected_total = Self::HEADER_SIZE + payload_len;
        if data.len() != expected_total {
            return Err(FalcoError::Protocol(format!(
                "CommandFrame size mismatch: got {} bytes, expected {}",
                data.len(),
                expected_total
            )));
        }

        // Payload
        let encrypted_payload = data[24..].to_vec();

        Ok(Self {
            command_id,
            flags,
            encrypted_payload,
        })
    }
}

/// Decision frame sent from the daemon to Falco.
///
/// Wire format:
/// ```text
/// [4: total_len][1: type=0x02][1: decision][2: reserved][16: command_id][4: result_len][N: result]
/// ```
#[derive(Debug, Clone)]
pub struct DaemonDecisionFrame {
    /// The command ID this decision is for.
    pub command_id: Uuid,
    /// The decision (ACK_REDIS or DO_NOT_ACK).
    pub decision: Decision,
    /// Optional result data.
    pub result: Vec<u8>,
}

impl DaemonDecisionFrame {
    /// Header size in bytes (type + decision + reserved + command_id + result_len).
    const HEADER_SIZE: usize = 1 + 1 + 2 + 16 + 4;

    /// Create a new DaemonDecisionFrame.
    pub fn new(command_id: Uuid, decision: Decision) -> Self {
        Self {
            command_id,
            decision,
            result: Vec::new(),
        }
    }

    /// Create a new DaemonDecisionFrame with result data.
    pub fn with_result(command_id: Uuid, decision: Decision, result: Vec<u8>) -> Self {
        Self {
            command_id,
            decision,
            result,
        }
    }

    /// Encode the frame to bytes (including length prefix).
    pub fn encode(&self) -> Vec<u8> {
        let result_len = self.result.len();
        let total_len = Self::HEADER_SIZE + result_len;

        let mut buf = Vec::with_capacity(4 + total_len);

        // Length prefix (excludes itself)
        buf.extend_from_slice(&(total_len as u32).to_le_bytes());

        // Frame type
        buf.push(FRAME_TYPE_DECISION);

        // Decision
        buf.push(self.decision.to_byte());

        // Reserved (2 bytes)
        buf.extend_from_slice(&[0u8, 0u8]);

        // Command ID (16 bytes)
        buf.extend_from_slice(self.command_id.as_bytes());

        // Result length
        buf.extend_from_slice(&(result_len as u32).to_le_bytes());

        // Result
        buf.extend_from_slice(&self.result);

        buf
    }

    /// Decode a DaemonDecisionFrame from bytes (excluding length prefix).
    pub fn decode(data: &[u8]) -> FalcoResult<Self> {
        if data.len() < Self::HEADER_SIZE {
            return Err(FalcoError::Protocol(format!(
                "DaemonDecisionFrame too short: {} bytes, need at least {}",
                data.len(),
                Self::HEADER_SIZE
            )));
        }

        // Frame type
        if data[0] != FRAME_TYPE_DECISION {
            return Err(FalcoError::Protocol(format!(
                "Expected DaemonDecisionFrame type {:#04x}, got {:#04x}",
                FRAME_TYPE_DECISION, data[0]
            )));
        }

        // Decision
        let decision = Decision::from_byte(data[1])?;

        // Reserved bytes at [2..4] are ignored

        // Command ID
        let command_id_bytes: [u8; 16] = data[4..20]
            .try_into()
            .map_err(|_| FalcoError::Protocol("Invalid command_id length".to_string()))?;
        let command_id = Uuid::from_bytes(command_id_bytes);

        // Result length
        let result_len = u32::from_le_bytes(
            data[20..24]
                .try_into()
                .map_err(|_| FalcoError::Protocol("Invalid result_len".to_string()))?,
        ) as usize;

        // Validate result length
        let expected_total = Self::HEADER_SIZE + result_len;
        if data.len() != expected_total {
            return Err(FalcoError::Protocol(format!(
                "DaemonDecisionFrame size mismatch: got {} bytes, expected {}",
                data.len(),
                expected_total
            )));
        }

        // Result
        let result = data[24..].to_vec();

        Ok(Self {
            command_id,
            decision,
            result,
        })
    }
}

/// Read a length-prefixed frame from a buffer.
///
/// Returns `None` if there isn't enough data for a complete frame.
/// Returns `Some((frame_data, consumed))` with the frame data (excluding length prefix)
/// and the total bytes consumed.
pub fn read_frame(buf: &[u8]) -> Option<(&[u8], usize)> {
    if buf.len() < 4 {
        return None;
    }

    let len = u32::from_le_bytes(buf[0..4].try_into().ok()?) as usize;

    if buf.len() < 4 + len {
        return None;
    }

    Some((&buf[4..4 + len], 4 + len))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_command_frame_roundtrip() {
        let command_id = Uuid::new_v4();
        let payload = vec![1, 2, 3, 4, 5, 6, 7, 8];

        let frame = CommandFrame::new(command_id, payload.clone());
        let encoded = frame.encode();

        // Decode (skip length prefix)
        let (frame_data, consumed) = read_frame(&encoded).unwrap();
        assert_eq!(consumed, encoded.len());

        let decoded = CommandFrame::decode(frame_data).unwrap();

        assert_eq!(decoded.command_id, command_id);
        assert_eq!(decoded.flags, 0);
        assert_eq!(decoded.encrypted_payload, payload);
    }

    #[test]
    fn test_daemon_decision_frame_roundtrip() {
        let command_id = Uuid::new_v4();
        let result = vec![10, 20, 30];

        let frame = DaemonDecisionFrame::with_result(command_id, Decision::AckRedis, result.clone());
        let encoded = frame.encode();

        let (frame_data, consumed) = read_frame(&encoded).unwrap();
        assert_eq!(consumed, encoded.len());

        let decoded = DaemonDecisionFrame::decode(frame_data).unwrap();

        assert_eq!(decoded.command_id, command_id);
        assert_eq!(decoded.decision, Decision::AckRedis);
        assert_eq!(decoded.result, result);
    }

    #[test]
    fn test_decision_bytes() {
        assert_eq!(Decision::AckRedis.to_byte(), DECISION_ACK_REDIS);
        assert_eq!(Decision::DoNotAck.to_byte(), DECISION_DO_NOT_ACK);

        assert_eq!(Decision::from_byte(DECISION_ACK_REDIS).unwrap(), Decision::AckRedis);
        assert_eq!(Decision::from_byte(DECISION_DO_NOT_ACK).unwrap(), Decision::DoNotAck);
        assert!(Decision::from_byte(0xFF).is_err());
    }

    #[test]
    fn test_empty_payload() {
        let command_id = Uuid::new_v4();
        let frame = CommandFrame::new(command_id, vec![]);
        let encoded = frame.encode();

        let (frame_data, _) = read_frame(&encoded).unwrap();
        let decoded = CommandFrame::decode(frame_data).unwrap();

        assert!(decoded.encrypted_payload.is_empty());
    }

    #[test]
    fn test_empty_result() {
        let command_id = Uuid::new_v4();
        let frame = DaemonDecisionFrame::new(command_id, Decision::DoNotAck);
        let encoded = frame.encode();

        let (frame_data, _) = read_frame(&encoded).unwrap();
        let decoded = DaemonDecisionFrame::decode(frame_data).unwrap();

        assert!(decoded.result.is_empty());
        assert_eq!(decoded.decision, Decision::DoNotAck);
    }

    #[test]
    fn test_read_frame_incomplete() {
        // Not enough for length prefix
        assert!(read_frame(&[1, 2, 3]).is_none());

        // Length says 100 bytes, but only 10 available
        let mut buf = vec![100, 0, 0, 0]; // length = 100
        buf.extend_from_slice(&[0; 10]);
        assert!(read_frame(&buf).is_none());
    }

    #[test]
    fn test_command_frame_wrong_type() {
        let mut data = vec![FRAME_TYPE_DECISION]; // Wrong type
        data.extend_from_slice(&[0; 23]); // Pad to minimum size

        assert!(CommandFrame::decode(&data).is_err());
    }

    #[test]
    fn test_daemon_decision_frame_wrong_type() {
        let mut data = vec![FRAME_TYPE_COMMAND]; // Wrong type
        data.extend_from_slice(&[0; 23]); // Pad to minimum size

        assert!(DaemonDecisionFrame::decode(&data).is_err());
    }
}
