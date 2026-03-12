//! Application wiring and lifecycle management.

mod init;
mod lifecycle;
mod startup_status;
mod state;

pub use init::run_daemon;
pub use lifecycle::{check_status, stop_daemon};
pub(crate) use startup_status::StartupStatusWriter;
pub use state::DaemonState;
