//! Application wiring and lifecycle management.

pub(crate) mod agent_cli;
mod init;
mod lifecycle;
mod space_scope;
mod startup_status;
mod state;

pub use init::run_daemon;
pub use lifecycle::{check_status, stop_daemon};
pub(crate) use space_scope::resolve_machine_space_scope;
pub(crate) use startup_status::StartupStatusWriter;
pub use state::DaemonState;
