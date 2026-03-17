use tauri::{AppHandle, Runtime};
use tauri_plugin_updater::UpdaterExt;
use url::Url;

const DEFAULT_UPDATER_ENDPOINT: &str =
    "https://github.com/imbhargav5/unbound.computer/releases/latest/download/latest.json";
const DEBUG_UPDATES_ENV: &str = "UNBOUND_DESKTOP_ALLOW_AUTO_UPDATE_IN_DEBUG";
const UPDATER_ENDPOINT_ENV: &str = "UNBOUND_DESKTOP_UPDATER_ENDPOINT";
const UPDATER_PUBLIC_KEY_ENV: &str = "TAURI_UPDATER_PUBLIC_KEY";

#[derive(Clone, Debug)]
pub struct AutoUpdateConfig {
    pub endpoint: Url,
    pub pubkey: String,
}

pub fn load_config() -> Result<Option<AutoUpdateConfig>, String> {
    if cfg!(debug_assertions) && !env_flag(DEBUG_UPDATES_ENV) {
        tracing::debug!(
            env = DEBUG_UPDATES_ENV,
            "desktop auto updates disabled in debug builds"
        );
        return Ok(None);
    }

    let Some(pubkey) = resolve_setting(
        UPDATER_PUBLIC_KEY_ENV,
        option_env!("TAURI_UPDATER_PUBLIC_KEY"),
    ) else {
        tracing::info!(
            env = UPDATER_PUBLIC_KEY_ENV,
            "desktop auto updates disabled; no updater public key configured"
        );
        return Ok(None);
    };

    let endpoint = resolve_setting(
        UPDATER_ENDPOINT_ENV,
        option_env!("UNBOUND_DESKTOP_UPDATER_ENDPOINT"),
    )
    .unwrap_or_else(|| DEFAULT_UPDATER_ENDPOINT.to_string());
    let endpoint = Url::parse(&endpoint)
        .map_err(|error| format!("invalid desktop updater endpoint {endpoint:?}: {error}"))?;

    Ok(Some(AutoUpdateConfig { endpoint, pubkey }))
}

pub fn spawn_startup_update_check<R: Runtime>(app: AppHandle<R>, config: AutoUpdateConfig) {
    let endpoint_for_log = config.endpoint.to_string();

    crate::observability::spawn_in_current_span(async move {
        let updater = match app
            .updater_builder()
            .pubkey(config.pubkey.clone())
            .endpoints(vec![config.endpoint.clone()])
            .and_then(|builder| builder.build())
        {
            Ok(updater) => updater,
            Err(error) => {
                tracing::error!(
                    error = %error,
                    endpoint = %endpoint_for_log,
                    "failed to configure desktop updater"
                );
                return;
            }
        };

        let update = match updater.check().await {
            Ok(update) => update,
            Err(error) => {
                tracing::error!(
                    error = %error,
                    endpoint = %endpoint_for_log,
                    "desktop update check failed"
                );
                return;
            }
        };

        let Some(update) = update else {
            tracing::debug!(
                endpoint = %endpoint_for_log,
                "desktop updater found no newer release"
            );
            return;
        };

        tracing::info!(
            current_version = %update.current_version,
            next_version = %update.version,
            endpoint = %endpoint_for_log,
            "desktop update available"
        );

        if let Err(error) = update.download_and_install(|_, _| {}, || {}).await {
            tracing::error!(
                error = %error,
                target_version = %update.version,
                "desktop update install failed"
            );
            return;
        }

        tracing::info!(
            target_version = %update.version,
            "desktop update installed; requesting restart"
        );
        app.request_restart();
    });
}

fn env_flag(name: &str) -> bool {
    std::env::var(name).ok().is_some_and(|value| {
        matches!(
            value.trim().to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "on"
        )
    })
}

fn resolve_setting(name: &str, compiled: Option<&'static str>) -> Option<String> {
    std::env::var(name)
        .ok()
        .and_then(non_empty)
        .or_else(|| compiled.and_then(|value| non_empty(value.to_string())))
}

fn non_empty(value: String) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}
