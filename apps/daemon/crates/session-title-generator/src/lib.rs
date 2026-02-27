//! Session Title Generator - Session title generation using Groq Llama 3.1 8B Instant.
//!
//! This crate provides functionality to generate concise session titles
//! based on the first user message in a session. It uses Groq's Llama 3.1
//! 8B Instant model (128k context) for fast, high-quality title generation.
//!
//! # Usage
//!
//! The title generation should only run on the very first user message
//! of a session:
//!
//! ```ignore
//! use session_title_generator::SessionTitleGenerator;
//!
//! // Create generator from environment variable
//! let generator = SessionTitleGenerator::from_env()?;
//!
//! // Generate title on first message
//! let title = generator.generate_title(
//!     "session-123",
//!     "Help me refactor this React component to use hooks"
//! ).await?;
//!
//! println!("Session title: {}", title);
//! // Output: "Refactor React Component to Hooks"
//! ```
//!
//! # Background Task
//!
//! For non-blocking title generation, use the spawn functions:
//!
//! ```ignore
//! use session_title_generator::spawn_title_generation_from_env;
//!
//! let handle = spawn_title_generation_from_env(
//!     "session-123".to_string(),
//!     "How do I implement authentication?".to_string(),
//! );
//!
//! // Continue with other work...
//!
//! // Later, get the result
//! let title = handle.await??;
//! ```

mod client;
mod error;
mod title_generator;

pub use client::GroqClient;
pub use error::{SessionTitleGeneratorError, SessionTitleGeneratorResult};
pub use title_generator::{
    spawn_title_generation, spawn_title_generation_from_env, SessionTitleGenerator,
};
