mod commands;
mod compatibility;

use commands::DesktopState;

fn main() {
    tauri::Builder::default()
        .manage(DesktopState::default())
        .invoke_handler(tauri::generate_handler![
            commands::desktop_bootstrap,
            commands::system_version,
            commands::system_check_dependencies,
            commands::board_list_companies,
            commands::board_create_company,
            commands::board_company_snapshot,
            commands::board_create_project,
            commands::board_create_issue,
            commands::board_get_issue,
            commands::board_update_issue,
            commands::board_list_issue_comments,
            commands::board_add_issue_comment,
            commands::board_checkout_issue,
            commands::board_approve_approval,
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
            commands::claude_send,
            commands::claude_status,
            commands::claude_stop,
            commands::git_status,
            commands::git_diff_file,
            commands::git_log,
            commands::git_branches,
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
            commands::desktop_reveal_in_finder,
            commands::desktop_open_external
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
