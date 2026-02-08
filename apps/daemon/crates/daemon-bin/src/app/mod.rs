//! Application wiring and lifecycle management.

pub(crate) mod falco_sidecar;
mod init;
mod lifecycle;
mod state;

pub use init::run_daemon;
pub use lifecycle::{check_status, stop_daemon};
pub use state::DaemonState;
