//! Deku: Claude CLI process manager.
//!
//! Deku manages the lifecycle of Claude CLI processes, handling:
//! - Process spawning with proper configuration
//! - Stdout streaming and JSON event parsing
//! - Process control (stop signals)
//!
//! # Architecture
//!
//! ```text
//! ┌─────────────────────────────────────────────────────────────────┐
//! │                           Daemon                                 │
//! │                                                                  │
//! │  IPC Handler ──► Deku::spawn() ──► ClaudeProcess                │
//! │                        │                  │                      │
//! │                        │                  │ stdout               │
//! │                        │                  ▼                      │
//! │                        │          ClaudeEventStream              │
//! │                        │                  │                      │
//! │                        │                  │ ClaudeEvent          │
//! │                        │                  ▼                      │
//! │                        └────────► EventHandler (callback)        │
//! └─────────────────────────────────────────────────────────────────┘
//! ```
//!
//! # Usage
//!
//! ```ignore
//! use deku::{ClaudeProcess, ClaudeConfig, ClaudeEvent};
//!
//! // Create configuration
//! let config = ClaudeConfig {
//!     message: "Hello, Claude!".to_string(),
//!     working_dir: "/path/to/repo".to_string(),
//!     resume_session_id: None,
//!     allowed_tools: None, // Uses default tools
//! };
//!
//! // Spawn the process
//! let process = ClaudeProcess::spawn(config).await?;
//!
//! // Get the event stream
//! let mut stream = process.take_stream();
//!
//! // Process events
//! while let Some(event) = stream.next().await {
//!     match event {
//!         ClaudeEvent::Json { event_type, raw } => {
//!             println!("Event: {} - {}", event_type, raw);
//!         }
//!         ClaudeEvent::Finished { success } => {
//!             println!("Process finished: {}", success);
//!             break;
//!         }
//!         _ => {}
//!     }
//! }
//! ```

mod config;
mod error;
mod event;
mod process;
mod stream;

pub use config::{ClaudeConfig, DEFAULT_ALLOWED_TOOLS};
pub use error::{DekuError, DekuResult};
pub use event::ClaudeEvent;
pub use process::ClaudeProcess;
pub use stream::ClaudeEventStream;
