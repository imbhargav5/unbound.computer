//! Core types, configuration, and utilities for the Unbound daemon.

mod config;
mod error;
pub mod hybrid_crypto;
mod logging;
mod paths;

pub use config::{Config, RelayConfig};
pub use error::{CoreError, CoreResult};
pub use hybrid_crypto::{decrypt_for_device, encrypt_for_device, generate_keypair};
pub use logging::init_logging;
pub use paths::Paths;

// Re-export git operations from piccolo for backward compatibility
pub use piccolo::{
    create_worktree, discard_changes, get_branches, get_file_diff, get_log, get_status,
    remove_worktree, stage_files, unstage_files, GitBranch, GitBranchesResult, GitCommit,
    GitDiffResult, GitFileStatus, GitLogResult, GitStatusFile, GitStatusResult,
};
