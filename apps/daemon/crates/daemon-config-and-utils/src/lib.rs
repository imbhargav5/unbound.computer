//! Core types, configuration, and utilities for the Unbound daemon.

mod config;
pub mod conversation_crypto;
mod error;
pub mod hybrid_crypto;
mod logging;
mod paths;
mod telemetry;

pub use config::{compile_time_web_app_url, Config, DEFAULT_WEB_APP_URL};
pub use conversation_crypto::{
    decrypt_conversation_message, encrypt_conversation_message,
    encrypt_conversation_message_with_nonce, ConversationCryptoError, EncryptedConversationPayload,
};
pub use error::{CoreError, CoreResult};
pub use hybrid_crypto::{decrypt_for_device, encrypt_for_device, generate_keypair};
pub use logging::{force_flush, init_logging, shutdown};
pub use paths::Paths;
pub use telemetry::{hash_identifier, summarize_response_body, url_host};

// Re-export git operations from git-ops for backward compatibility
pub use git_ops::{
    create_worktree, discard_changes, get_branches, get_file_diff, get_log, get_status,
    remove_worktree, stage_files, unstage_files, GitBranch, GitBranchesResult, GitCommit,
    GitDiffResult, GitFileStatus, GitLogResult, GitStatusFile, GitStatusResult,
};
