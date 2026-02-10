/// Build the directional session-secrets channel name.
///
/// Format: `session:secrets:{sender_device_id}:{receiver_device_id}`
pub fn build_session_secrets_channel(sender_device_id: &str, receiver_device_id: &str) -> String {
    format!("session:secrets:{sender_device_id}:{receiver_device_id}")
}

#[cfg(test)]
mod tests {
    use super::build_session_secrets_channel;

    #[test]
    fn builds_pair_channel_name() {
        assert_eq!(
            build_session_secrets_channel("sender-1", "receiver-2"),
            "session:secrets:sender-1:receiver-2"
        );
    }
}
