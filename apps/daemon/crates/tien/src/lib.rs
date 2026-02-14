//! # Tien: System Dependency Detection
//!
//! Tien provides system dependency checking for the Unbound daemon.
//! It detects whether required tools (Claude Code CLI, GitHub CLI)
//! are installed on the user's system.
//!
//! ## Overview
//!
//! The crate exposes pure async functions that check for dependencies
//! by spawning a login shell and running `which`. This ensures the
//! user's full PATH is available (including nvm, homebrew, etc.).
//!
//! ## Key Operations
//!
//! | Function | Description |
//! |----------|-------------|
//! | [`check_dependency`] | Check if a single dependency is installed |
//! | [`check_all`] | Check all required dependencies concurrently |
//! | [`collect_capabilities`] | Collect the canonical capabilities payload |
//!
//! ## Example Usage
//!
//! ```ignore
//! use tien::{check_all, check_dependency};
//!
//! // Check a single dependency
//! let claude = check_dependency("claude").await?;
//! println!("Claude installed: {}", claude.installed);
//!
//! // Check all dependencies at once
//! let result = check_all().await?;
//! if !result.claude.installed {
//!     println!("Claude Code CLI is required!");
//! }
//! ```

mod error;
mod operations;
mod types;

pub use error::TienError;
pub use operations::{check_all, check_dependency, collect_capabilities};
pub use types::{
    Capabilities, CapabilitiesMetadata, CliCapabilities, DependencyCheckResult, DependencyInfo,
    ToolCapabilities,
};
