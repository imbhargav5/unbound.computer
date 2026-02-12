//! # Bakugou
//!
//! Typed GitHub CLI orchestration for the Unbound daemon.
//!
//! Bakugou owns process execution, timeout control, output parsing, and
//! error normalization for `gh` pull-request workflows.

mod command_runner;
mod error;
mod operations;
mod types;

pub use error::BakugouError;
pub use operations::{auth_status, pr_checks, pr_create, pr_list, pr_merge, pr_view};
pub use types::{
    AuthStatusInput, AuthStatusResult, AuthStatusHost,
    PrCheckItem, PrChecksInput, PrChecksResult, PrChecksSummary,
    PrCreateInput, PrCreateResult,
    PrListInput, PrListResult, PrListState,
    PrMergeInput, PrMergeMethod, PrMergeResult,
    PrViewInput,
    PullRequestAuthor, PullRequestDetail, PullRequestLabel,
};
