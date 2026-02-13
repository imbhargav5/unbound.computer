//! Billing handlers.

use crate::app::DaemonState;
use daemon_ipc::{IpcServer, Method, Response};
use tracing::info;

const BILLING_CACHE_STALE_AFTER_MS: i64 = 5 * 60 * 1000;
const BILLING_DELAY_HINT_MINUTES: i64 = 5;

/// Register billing handlers.
pub async fn register(server: &IpcServer, state: DaemonState) {
    server
        .register_handler(Method::BillingUsageStatus, move |req| {
            let state = state.clone();
            async move {
                let sync_context = match state.auth_runtime.current_sync_context() {
                    Ok(Some(sync_context)) => sync_context,
                    _ => return Response::success(&req.id, unavailable_payload()),
                };

                let snapshot = {
                    let guard = state.billing_quota_cache.lock().unwrap();
                    guard.snapshot.clone()
                };

                let Some(snapshot) = snapshot else {
                    return Response::success(&req.id, unavailable_payload());
                };

                if snapshot.user_id != sync_context.user_id || snapshot.device_id != sync_context.device_id {
                    return Response::success(&req.id, unavailable_payload());
                }

                let now_ms = chrono::Utc::now().timestamp_millis();
                let stale = now_ms - snapshot.fetched_at_ms > BILLING_CACHE_STALE_AFTER_MS;
                let fetched_at = chrono::DateTime::<chrono::Utc>::from_timestamp_millis(
                    snapshot.fetched_at_ms,
                )
                .map(|dt| dt.to_rfc3339());

                Response::success(
                    &req.id,
                    serde_json::json!({
                        "available": true,
                        "stale": stale,
                        "delay_hint_minutes": BILLING_DELAY_HINT_MINUTES,
                        "fetched_at": fetched_at,
                        "status": {
                            "plan": snapshot.plan,
                            "gateway": snapshot.gateway,
                            "period_start": snapshot.period_start,
                            "period_end": snapshot.period_end,
                            "commands_limit": snapshot.commands_limit,
                            "commands_used": snapshot.commands_used,
                            "commands_remaining": snapshot.commands_remaining,
                            "enforcement_state": snapshot.enforcement_state,
                            "updated_at": snapshot.updated_at,
                        }
                    }),
                )
            }
        })
        .await;

    info!("Registered billing handlers");
}

fn unavailable_payload() -> serde_json::Value {
    serde_json::json!({
        "available": false,
        "stale": true,
        "delay_hint_minutes": BILLING_DELAY_HINT_MINUTES,
        "status": serde_json::Value::Null,
        "fetched_at": serde_json::Value::Null,
    })
}
