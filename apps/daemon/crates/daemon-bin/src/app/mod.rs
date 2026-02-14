//! Application wiring and lifecycle management.

pub(crate) mod ably_sidecar;
pub(crate) mod falco_sidecar;
mod init;
mod lifecycle;
pub(crate) mod nagato_server;
pub(crate) mod nagato_sidecar;
pub(crate) mod sidecar_logs;
pub(crate) mod sidecar_supervisor;
mod state;

pub use init::run_daemon;
pub use lifecycle::{check_status, stop_daemon};
pub use state::{BillingQuotaSnapshot, DaemonState};
