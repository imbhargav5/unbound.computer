//! Session title generator with side effects.
//!
//! This module provides the main entry point for generating session titles
//! on the first user message of a session.

use crate::client::GroqClient;
use crate::error::YamchaResult;

/// Session title generator that runs on the first user message.
///
/// This struct encapsulates the logic for generating session titles
/// using Groq's Llama 3.1 8B Instant model.
pub struct SessionTitleGenerator {
    client: GroqClient,
}

impl SessionTitleGenerator {
    /// Create a new session title generator with an explicit API key.
    pub fn new(api_key: impl Into<String>) -> Self {
        Self {
            client: GroqClient::new(api_key),
        }
    }

    /// Create a new session title generator using the GROQ_API_KEY environment variable.
    ///
    /// # Errors
    /// Returns an error if the GROQ_API_KEY environment variable is not set.
    pub fn from_env() -> YamchaResult<Self> {
        Ok(Self {
            client: GroqClient::from_env()?,
        })
    }

    /// Generate a title for the session based on the first user message.
    ///
    /// This method should only be called once per session, on the very first
    /// user message. It generates a title and logs the result as a side effect.
    ///
    /// # Arguments
    /// * `session_id` - The session identifier for logging context
    /// * `first_message` - The first user message in the session
    ///
    /// # Returns
    /// The generated session title.
    pub async fn generate_title(
        &self,
        session_id: &str,
        first_message: &str,
    ) -> YamchaResult<String> {
        tracing::debug!(
            session_id = %session_id,
            message_preview = %truncate_message(first_message, 100),
            "Generating session title"
        );

        let title = self.client.generate_session_title(first_message).await?;

        // Side effect: Log the generated title
        tracing::info!(
            session_id = %session_id,
            title = %title,
            "Session title generated"
        );

        Ok(title)
    }

    /// Generate a title and execute a callback with the result.
    ///
    /// This is useful when you want to perform additional side effects
    /// with the generated title (e.g., save to database, send to UI).
    ///
    /// # Arguments
    /// * `session_id` - The session identifier for logging context
    /// * `first_message` - The first user message in the session
    /// * `on_title` - Callback to execute with the generated title
    pub async fn generate_title_with_callback<F>(
        &self,
        session_id: &str,
        first_message: &str,
        on_title: F,
    ) -> YamchaResult<String>
    where
        F: FnOnce(&str),
    {
        let title = self.generate_title(session_id, first_message).await?;
        on_title(&title);
        Ok(title)
    }
}

/// Truncate a message for logging purposes.
fn truncate_message(message: &str, max_len: usize) -> String {
    if message.len() <= max_len {
        message.to_string()
    } else {
        format!("{}...", &message[..max_len])
    }
}

/// Spawn a background task to generate a session title.
///
/// This function spawns a tokio task to generate the title asynchronously,
/// allowing the caller to continue without waiting for the API response.
///
/// # Arguments
/// * `api_key` - The Groq API key
/// * `session_id` - The session identifier
/// * `first_message` - The first user message
///
/// # Returns
/// A JoinHandle for the spawned task.
pub fn spawn_title_generation(
    api_key: String,
    session_id: String,
    first_message: String,
) -> tokio::task::JoinHandle<YamchaResult<String>> {
    tokio::spawn(async move {
        let generator = SessionTitleGenerator::new(api_key);
        generator.generate_title(&session_id, &first_message).await
    })
}

/// Spawn a background task to generate a session title using the GROQ_API_KEY env var.
///
/// # Arguments
/// * `session_id` - The session identifier
/// * `first_message` - The first user message
///
/// # Returns
/// A JoinHandle for the spawned task.
pub fn spawn_title_generation_from_env(
    session_id: String,
    first_message: String,
) -> tokio::task::JoinHandle<YamchaResult<String>> {
    tokio::spawn(async move {
        let generator = SessionTitleGenerator::from_env()?;
        generator.generate_title(&session_id, &first_message).await
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_truncate_message_short() {
        let msg = "Hello world";
        assert_eq!(truncate_message(msg, 100), "Hello world");
    }

    #[test]
    fn test_truncate_message_long() {
        let msg = "This is a very long message that should be truncated";
        let truncated = truncate_message(msg, 20);
        assert_eq!(truncated, "This is a very long ...");
    }
}
