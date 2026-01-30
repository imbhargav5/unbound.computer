//! External process communication (machines).
//!
//! This module handles spawning and managing external processes:
//! - Claude CLI for AI interactions
//! - Terminal commands for shell execution
//! - Git operations for repository management

pub mod claude;
pub mod git;
pub mod terminal;
