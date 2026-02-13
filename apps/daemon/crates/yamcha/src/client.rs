//! Groq API client for session title generation.
//!
//! This module provides a client for calling Groq's Llama 3.1 8B Instant model
//! to generate concise session titles based on the first user message.

use crate::error::{YamchaError, YamchaResult};
use serde::{Deserialize, Serialize};
use std::collections::hash_map::DefaultHasher;
use std::hash::{Hash, Hasher};

const GROQ_API_URL: &str = "https://api.groq.com/openai/v1/chat/completions";
const MODEL: &str = "llama-3.1-8b-instant";

fn summarize_response_body(body: &str) -> String {
    let mut hasher = DefaultHasher::new();
    body.hash(&mut hasher);
    format!("len={},digest={:016x}", body.len(), hasher.finish())
}

/// Groq API client for generating session titles.
#[derive(Clone, Debug)]
pub struct GroqClient {
    http_client: reqwest::Client,
    api_key: String,
}

#[derive(Debug, Serialize)]
struct ChatCompletionRequest {
    model: String,
    messages: Vec<Message>,
    max_tokens: u32,
    temperature: f32,
}

#[derive(Debug, Serialize, Deserialize)]
struct Message {
    role: String,
    content: String,
}

#[derive(Debug, Deserialize)]
struct ChatCompletionResponse {
    choices: Vec<Choice>,
}

#[derive(Debug, Deserialize)]
struct Choice {
    message: MessageResponse,
}

#[derive(Debug, Deserialize)]
struct MessageResponse {
    content: String,
}

impl GroqClient {
    /// Create a new Groq client with the given API key.
    ///
    /// # Arguments
    /// * `api_key` - The Groq API key for authentication
    pub fn new(api_key: impl Into<String>) -> Self {
        Self {
            http_client: reqwest::Client::new(),
            api_key: api_key.into(),
        }
    }

    /// Create a new Groq client from the GROQ_API_KEY environment variable.
    ///
    /// # Errors
    /// Returns `YamchaError::MissingApiKey` if the environment variable is not set.
    pub fn from_env() -> YamchaResult<Self> {
        let api_key = std::env::var("GROQ_API_KEY").map_err(|_| YamchaError::MissingApiKey)?;
        Ok(Self::new(api_key))
    }

    /// Generate a session title based on the first user message.
    ///
    /// This method calls Groq's Llama 3.1 8B Instant model to generate
    /// a concise, descriptive title for the session.
    ///
    /// # Arguments
    /// * `first_message` - The first user message in the session
    ///
    /// # Returns
    /// A short title (typically 3-8 words) describing the session topic.
    pub async fn generate_session_title(&self, first_message: &str) -> YamchaResult<String> {
        let system_prompt = include_str!("system_prompt.txt");

        let request = ChatCompletionRequest {
            model: MODEL.to_string(),
            messages: vec![
                Message {
                    role: "system".to_string(),
                    content: system_prompt.to_string(),
                },
                Message {
                    role: "user".to_string(),
                    content: first_message.to_string(),
                },
            ],
            max_tokens: 32,
            temperature: 0.3,
        };

        tracing::debug!("Sending title generation request to Groq");

        let response = self
            .http_client
            .post(GROQ_API_URL)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status().as_u16();
            let body = response.text().await.unwrap_or_default();
            let body_summary = summarize_response_body(&body);
            tracing::error!(status, body_summary = %body_summary, "Groq API error");
            return Err(YamchaError::ApiError {
                status,
                message: format!("upstream error ({body_summary})"),
            });
        }

        let completion: ChatCompletionResponse = response.json().await?;

        let title = completion
            .choices
            .first()
            .map(|c| c.message.content.trim().to_string())
            .ok_or_else(|| YamchaError::InvalidResponse("No choices in response".to_string()))?;

        tracing::info!(title = %title, "Generated session title");

        Ok(title)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_creation() {
        let client = GroqClient::new("test-api-key");
        assert_eq!(client.api_key, "test-api-key");
    }

    #[test]
    fn test_request_serialization() {
        let request = ChatCompletionRequest {
            model: MODEL.to_string(),
            messages: vec![Message {
                role: "user".to_string(),
                content: "Hello".to_string(),
            }],
            max_tokens: 32,
            temperature: 0.3,
        };

        let json = serde_json::to_string(&request).unwrap();
        assert!(json.contains("llama-3.1-8b-instant"));
        assert!(json.contains("Hello"));
    }

    #[test]
    fn test_from_env_missing_api_key() {
        // Temporarily remove the env var if it exists
        let original = std::env::var("GROQ_API_KEY").ok();
        std::env::remove_var("GROQ_API_KEY");

        let result = GroqClient::from_env();
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), YamchaError::MissingApiKey));

        // Restore the original value if it existed
        if let Some(key) = original {
            std::env::set_var("GROQ_API_KEY", key);
        }
    }

    #[test]
    fn test_from_env_with_api_key() {
        // Set a test API key
        let original = std::env::var("GROQ_API_KEY").ok();
        std::env::set_var("GROQ_API_KEY", "test-key-from-env");

        let result = GroqClient::from_env();
        assert!(result.is_ok());
        assert_eq!(result.unwrap().api_key, "test-key-from-env");

        // Restore the original value or remove the test key
        match original {
            Some(key) => std::env::set_var("GROQ_API_KEY", key),
            None => std::env::remove_var("GROQ_API_KEY"),
        }
    }
}
