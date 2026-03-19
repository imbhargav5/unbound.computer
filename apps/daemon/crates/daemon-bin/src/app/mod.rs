//! Application wiring and lifecycle management.

mod agent_runs;
mod init;
mod issue_workspaces;
mod lifecycle;
mod startup_status;
mod state;

pub use agent_runs::{AgentRunCoordinator, AgentRunEnqueueRequest};
pub use init::run_daemon;
pub(crate) use issue_workspaces::{
    ensure_issue_workspace, ensure_workspace_repository, issue_has_attached_workspace_target,
};
pub use lifecycle::{check_status, stop_daemon};
pub(crate) use startup_status::StartupStatusWriter;
pub use state::DaemonState;
