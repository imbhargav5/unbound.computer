mod commands;
mod compatibility;
mod observability;
mod updater;

use commands::DesktopState;

fn main() {
    observability::init();

    let updater_config = match updater::load_config() {
        Ok(config) => config,
        Err(error) => {
            tracing::error!(error = %error, "desktop auto update configuration is invalid");
            None
        }
    };

    let mut builder = tauri::Builder::default();
    if let Some(config) = updater_config.as_ref() {
        builder = builder.plugin(
            tauri_plugin_updater::Builder::new()
                .pubkey(config.pubkey.clone())
                .build(),
        );
    }

    let updater_config_for_setup = updater_config.clone();
    let run_result = builder
        .manage(DesktopState::default())
        .setup(move |app| {
            tracing::info!(
                operation = "desktop.startup",
                feature = "desktop",
                result = "ok",
                app_version = env!("CARGO_PKG_VERSION"),
                "desktop tauri app ready"
            );
            if let Some(config) = updater_config_for_setup.clone() {
                updater::spawn_startup_update_check(app.handle().clone(), config);
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::desktop_bootstrap,
            commands::system_version,
            commands::system_check_dependencies,
            commands::space_get_current,
            commands::board_list_companies,
            commands::board_create_company,
            commands::board_update_company,
            commands::board_create_agent,
            commands::board_update_agent,
            commands::board_company_snapshot,
            commands::board_dashboard_overview,
            commands::board_create_project,
            commands::board_update_project,
            commands::board_delete_project,
            commands::board_create_issue,
            commands::board_get_issue,
            commands::board_update_issue,
            commands::board_list_issue_comments,
            commands::board_list_issue_attachments,
            commands::board_add_issue_attachment,
            commands::board_list_issue_runs,
            commands::board_list_issue_run_card_updates,
            commands::board_add_issue_comment,
            commands::board_checkout_issue,
            commands::board_approve_approval,
            commands::board_list_agent_runs,
            commands::board_list_agent_live_run_counts,
            commands::board_get_agent_run,
            commands::board_list_agent_run_events,
            commands::board_read_agent_run_log,
            commands::board_invoke_agent_run,
            commands::board_cancel_agent_run,
            commands::board_retry_agent_run,
            commands::board_resume_agent_run,
            commands::repository_list,
            commands::repository_add,
            commands::repository_remove,
            commands::repository_get_settings,
            commands::repository_update_settings,
            commands::repository_list_files,
            commands::repository_read_file,
            commands::repository_write_file,
            commands::repository_replace_file_range,
            commands::session_list,
            commands::session_create,
            commands::session_get,
            commands::session_update,
            commands::message_list,
            commands::agent_send,
            commands::agent_status,
            commands::agent_stop,
            commands::claude_send,
            commands::claude_status,
            commands::claude_stop,
            commands::git_status,
            commands::git_diff_file,
            commands::git_log,
            commands::git_branches,
            commands::git_worktrees,
            commands::git_stage,
            commands::git_unstage,
            commands::git_discard,
            commands::git_commit,
            commands::git_push,
            commands::terminal_run,
            commands::terminal_status,
            commands::terminal_stop,
            commands::session_subscribe,
            commands::session_unsubscribe,
            commands::settings_get,
            commands::settings_update,
            commands::desktop_pick_repository_directory,
            commands::desktop_pick_file,
            commands::desktop_reveal_in_finder,
            commands::desktop_open_external
        ])
        .run(tauri::generate_context!());

    observability::shutdown();
    run_result.expect("error while running tauri application");
}
