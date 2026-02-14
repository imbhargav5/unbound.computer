//! Runtime sidecar supervision for daemon-ably, falco, and nagato.

use crate::app::DaemonState;
use crate::auth::common::reconcile_sidecars_with_auth;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;
use tokio::time::{sleep, Duration};
use tracing::{debug, info, warn};

const HEALTHY_POLL_INTERVAL: Duration = Duration::from_secs(5);
const BACKOFF_BASE: Duration = Duration::from_secs(1);
const BACKOFF_MAX: Duration = Duration::from_secs(30);
const BACKOFF_CAP_EXPONENT: u32 = 5;

/// Spawn the daemon sidecar supervisor.
pub fn spawn_sidecar_supervisor(
    state: DaemonState,
    mut shutdown: oneshot::Receiver<()>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut backoff = SupervisorBackoff::default();
        let mut interval = HEALTHY_POLL_INTERVAL;

        loop {
            tokio::select! {
                _ = &mut shutdown => {
                    info!("Sidecar supervisor received shutdown signal");
                    break;
                }
                _ = sleep(interval) => {
                    let healthy = reconcile_sidecars_with_auth(&state).await;
                    if healthy {
                        if backoff.failures > 0 {
                            info!(
                                previous_failures = backoff.failures,
                                "Sidecar supervisor recovered after restart failures"
                            );
                        }
                        backoff.reset();
                        interval = HEALTHY_POLL_INTERVAL;
                        continue;
                    }

                    interval = backoff.next_delay();
                    warn!(
                        failure_count = backoff.failures,
                        next_check_ms = interval.as_millis(),
                        "Sidecar supervisor detected unavailable sidecar state; backing off restart attempts"
                    );
                }
            }
        }

        debug!("Sidecar supervisor task stopped");
    })
}

#[derive(Debug, Default)]
struct SupervisorBackoff {
    failures: u32,
}

impl SupervisorBackoff {
    fn reset(&mut self) {
        self.failures = 0;
    }

    fn next_delay(&mut self) -> Duration {
        self.failures = self.failures.saturating_add(1);
        let shift = self.failures.min(BACKOFF_CAP_EXPONENT);
        let multiplier = 1u32 << shift;
        let delay = BACKOFF_BASE.saturating_mul(multiplier);
        if delay > BACKOFF_MAX {
            BACKOFF_MAX
        } else {
            delay
        }
    }
}
