//! Keyboard event handling for the TUI.

use super::app::{App, InputMode, Panel, VcFocus};
use super::components::account_dialog::{get_selected_action, DialogAction};
use anyhow::Result;
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyModifiers};
use std::time::Duration;

/// Enter prompt mode if a prompt is pending.
fn enter_prompt_mode_if_needed(app: &mut App) {
    if app.pending_prompt.is_some() && app.input_mode != InputMode::Prompt {
        app.input_mode = InputMode::Prompt;
        app.active_panel = Panel::Chat;
    }
}

/// Handle input events. Returns true if the app should quit.
pub async fn handle_events(app: &mut App) -> Result<bool> {
    // Poll for events with a small timeout
    if event::poll(Duration::from_millis(100))? {
        if let Event::Key(key) = event::read()? {
            // Clear status message on any key press
            app.clear_status_message();

            return Ok(handle_key_event(app, key).await);
        }
    }

    Ok(false)
}

/// Handle a key event. Returns true if the app should quit.
async fn handle_key_event(app: &mut App, key: KeyEvent) -> bool {
    // Handle account dialog first (modal overlay)
    if app.show_account_dialog {
        return handle_account_dialog(app, key).await;
    }

    // Check if we should enter prompt mode
    enter_prompt_mode_if_needed(app);

    // Handle prompt mode separately
    if app.input_mode == InputMode::Prompt {
        return handle_prompt_mode(app, key).await;
    }

    // Handle edit mode separately
    if app.input_mode == InputMode::Editing {
        return handle_edit_mode(app, key).await;
    }

    // Handle terminal input mode (typing commands in terminal)
    if app.active_panel == Panel::VersionControl && app.vc_focus == VcFocus::Terminal {
        return handle_terminal_input(app, key).await;
    }

    // Normal mode
    match key.code {
        // Quit
        KeyCode::Char('q') => return true,
        KeyCode::Esc => {
            if app.input_mode == InputMode::Editing {
                app.exit_edit_mode();
            }
        }

        // Panel navigation
        KeyCode::Tab => {
            if key.modifiers.contains(KeyModifiers::SHIFT) {
                app.prev_panel();
            } else {
                app.next_panel();
            }
        }
        KeyCode::BackTab => app.prev_panel(),

        // Movement
        KeyCode::Char('j') | KeyCode::Down => handle_down(app).await,
        KeyCode::Char('k') | KeyCode::Up => handle_up(app).await,
        KeyCode::Char('h') | KeyCode::Left => handle_left(app),
        KeyCode::Char('l') | KeyCode::Right => handle_right(app),

        // Actions
        KeyCode::Enter => {
            handle_enter(app).await;
        }
        KeyCode::Char('i') => {
            // Switch to chat panel and enter edit mode
            app.active_panel = Panel::Chat;
            app.enter_edit_mode();
        }
        KeyCode::Char('n') => {
            handle_new(app, false).await;
        }
        KeyCode::Char('N') => {
            handle_new(app, true).await;
        }
        KeyCode::Char('d') => {
            handle_delete(app).await;
        }
        KeyCode::Char('r') => {
            // Refresh data
            if app.active_panel == Panel::VersionControl {
                // Refresh git status
                if let Err(e) = app.refresh_git_status().await {
                    app.set_status_message(format!("Git refresh failed: {}", e));
                } else {
                    app.set_status_message("Git status refreshed".to_string());
                }
            } else if let Err(e) = app.refresh_data().await {
                app.set_status_message(format!("Refresh failed: {}", e));
            } else {
                app.set_status_message("Data refreshed".to_string());
            }
        }
        KeyCode::Char('t') => {
            // Focus terminal in version control panel
            if app.active_panel == Panel::VersionControl {
                app.vc_focus = VcFocus::Terminal;
            }
        }
        KeyCode::Char('f') => {
            // Focus file list in version control panel
            if app.active_panel == Panel::VersionControl {
                app.vc_focus = VcFocus::FileList;
            }
        }

        // Jump to bottom of chat (re-enable auto-scroll)
        KeyCode::Char('G') => {
            if app.active_panel == Panel::Chat {
                app.chat_auto_scroll = true;
                app.chat_scroll_offset = 0; // Will be set to max by render
            }
        }

        // Jump to top of chat
        KeyCode::Char('g') => {
            if app.active_panel == Panel::Chat {
                app.chat_scroll_offset = 0;
                app.chat_auto_scroll = false;
            }
        }

        // Account dialog
        KeyCode::Char('u') => {
            app.toggle_account_dialog();
        }

        // Help
        KeyCode::Char('?') => {
            app.set_status_message(
                "Tab: panel | j/k: move | u: account | n: new | N: worktree | d: delete | r: refresh | q: quit"
                    .to_string(),
            );
        }

        _ => {}
    }

    false
}

/// Handle prompt mode input (AskUserQuestion). Returns true if the app should quit.
async fn handle_prompt_mode(app: &mut App, key: KeyEvent) -> bool {
    let prompt = match app.pending_prompt.as_mut() {
        Some(p) => p,
        None => {
            // No prompt, exit prompt mode
            app.input_mode = InputMode::Normal;
            return false;
        }
    };

    let option_count = prompt.options.len();
    if option_count == 0 {
        app.input_mode = InputMode::Normal;
        app.pending_prompt = None;
        return false;
    }

    match key.code {
        KeyCode::Esc => {
            // Cancel prompt (option: could send a cancel response)
            app.input_mode = InputMode::Normal;
            app.pending_prompt = None;
            app.set_status_message("Prompt cancelled".to_string());
        }
        KeyCode::Up | KeyCode::Char('k') => {
            // Move selection up
            if prompt.selected_option > 0 {
                prompt.selected_option -= 1;
            } else {
                prompt.selected_option = option_count - 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            // Move selection down
            if prompt.selected_option < option_count - 1 {
                prompt.selected_option += 1;
            } else {
                prompt.selected_option = 0;
            }
        }
        KeyCode::Char(c) if c.is_ascii_digit() => {
            // Quick select by number (1-9)
            let num = c.to_digit(10).unwrap_or(0) as usize;
            if num >= 1 && num <= option_count {
                prompt.selected_option = num - 1;
            }
        }
        KeyCode::Enter => {
            // Submit selection
            let selected_idx = prompt.selected_option;
            let selected_label = prompt.options.get(selected_idx)
                .map(|o| o.label.clone())
                .unwrap_or_default();
            let _tool_use_id = prompt.tool_use_id.clone();

            // Clear prompt state
            app.input_mode = InputMode::Normal;
            app.pending_prompt = None;

            // TODO: Send the selected option back to Claude via daemon
            // For now, just show a status message
            app.set_status_message(format!("Selected: {}", selected_label));
        }
        _ => {}
    }

    false
}

/// Handle account dialog input. Returns true if the app should quit.
async fn handle_account_dialog(app: &mut App, key: KeyEvent) -> bool {
    match key.code {
        KeyCode::Esc => {
            app.close_account_dialog();
        }
        KeyCode::Up | KeyCode::Char('k') => {
            if app.account_dialog_selected > 0 {
                app.account_dialog_selected -= 1;
            }
        }
        KeyCode::Down | KeyCode::Char('j') => {
            // Currently only one option (logout)
        }
        KeyCode::Enter => {
            let action = get_selected_action(app);
            app.close_account_dialog();

            match action {
                DialogAction::Logout => {
                    match app.logout().await {
                        Ok(()) => {
                            // Quit the CLI after successful logout
                            return true;
                        }
                        Err(e) => {
                            app.set_status_message(format!("Logout failed: {}", e));
                        }
                    }
                }
                DialogAction::None => {}
            }
        }
        _ => {}
    }

    false
}

/// Handle terminal input when focused on terminal section.
async fn handle_terminal_input(app: &mut App, key: KeyEvent) -> bool {
    match key.code {
        KeyCode::Esc => {
            // Exit terminal focus
            app.vc_focus = VcFocus::FileList;
        }
        KeyCode::Enter => {
            // Run the command
            if !app.terminal_input.is_empty() && !app.terminal_running {
                let command = app.terminal_input.clone();
                if let Err(e) = app.run_terminal_command(&command).await {
                    app.set_status_message(format!("Terminal error: {}", e));
                }
            }
        }
        KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
            // Stop running command
            if app.terminal_running {
                if let Err(e) = app.stop_terminal().await {
                    app.set_status_message(format!("Failed to stop: {}", e));
                }
            } else {
                // Clear input
                app.terminal_input.clear();
            }
        }
        KeyCode::Char(c) => {
            if !app.terminal_running {
                app.terminal_input.push(c);
            }
        }
        KeyCode::Backspace => {
            if !app.terminal_running {
                app.terminal_input.pop();
            }
        }
        _ => {}
    }

    false
}

/// Handle key events in edit mode. Returns true if the app should quit.
async fn handle_edit_mode(app: &mut App, key: KeyEvent) -> bool {
    match key.code {
        KeyCode::Esc => {
            app.exit_edit_mode();
        }
        KeyCode::Enter => {
            // Submit the message if there's content
            if !app.chat_input.is_empty() {
                let content = app.chat_input.clone();
                app.chat_input.clear();

                match app.send_message(&content).await {
                    Ok(()) => {
                        app.set_status_message("Message sent".to_string());
                    }
                    Err(e) => {
                        app.set_status_message(format!("Failed to send: {}", e));
                    }
                }
            }
            app.exit_edit_mode();
        }
        KeyCode::Char(c) => {
            app.chat_input.push(c);
        }
        KeyCode::Backspace => {
            app.chat_input.pop();
        }
        _ => {}
    }

    false
}

/// Handle down movement.
async fn handle_down(app: &mut App) {
    match app.active_panel {
        Panel::Sidebar => {
            app.sidebar_down();
            // Auto-select session on navigation
            auto_subscribe_sidebar_session(app).await;
        }
        Panel::Chat => {
            // Scroll down - show later content (increase offset)
            app.chat_scroll_offset = app.chat_scroll_offset.saturating_add(1);
            app.chat_auto_scroll = false; // User took control
        }
        Panel::VersionControl => {
            if app.vc_focus == VcFocus::FileList && app.selected_file_idx < app.files.len().saturating_sub(1) {
                app.selected_file_idx += 1;
                // Fetch diff for newly selected file
                if let Err(e) = app.fetch_selected_file_diff().await {
                    app.set_status_message(format!("Failed to fetch diff: {}", e));
                }
            } else if app.vc_focus == VcFocus::Terminal {
                // Scroll terminal output down
                app.terminal_scroll = app.terminal_scroll.saturating_add(1);
            }
        }
    }
}

/// Handle up movement.
async fn handle_up(app: &mut App) {
    match app.active_panel {
        Panel::Sidebar => {
            app.sidebar_up();
            // Auto-select session on navigation
            auto_subscribe_sidebar_session(app).await;
        }
        Panel::Chat => {
            // Scroll up - show earlier content (decrease offset)
            app.chat_scroll_offset = app.chat_scroll_offset.saturating_sub(1);
            app.chat_auto_scroll = false; // User took control
        }
        Panel::VersionControl => {
            if app.vc_focus == VcFocus::FileList && app.selected_file_idx > 0 {
                app.selected_file_idx -= 1;
                // Note: diff will be fetched on next handle_down or handle_enter
            } else if app.vc_focus == VcFocus::Terminal {
                // Scroll terminal output up
                app.terminal_scroll = app.terminal_scroll.saturating_sub(1);
            }
        }
    }
}

/// Handle left movement (collapse in sidebar).
fn handle_left(app: &mut App) {
    if app.active_panel == Panel::Sidebar {
        if let Some(repo) = app.selected_repo() {
            let repo_id = repo.id.clone();
            app.expanded_repos.remove(&repo_id);
        }
    }
}

/// Handle right movement (expand in sidebar).
fn handle_right(app: &mut App) {
    if app.active_panel == Panel::Sidebar {
        if let Some(repo) = app.selected_repo() {
            let repo_id = repo.id.clone();
            app.expanded_repos.insert(repo_id);
        }
    }
}

/// Handle enter key.
async fn handle_enter(app: &mut App) {
    match app.active_panel {
        Panel::Sidebar => {
            // Toggle repo expansion or select session
            if app.selected_session_idx == 0 {
                app.toggle_repo_expansion();
            } else {
                // Session selected - subscribe to it for real-time updates
                if let Some(session_id) = app.selected_session_id.clone() {
                    match app.subscribe_to_session(&session_id).await {
                        Ok(()) => {
                            app.set_status_message("Subscribed to session".to_string());
                        }
                        Err(e) => {
                            app.set_status_message(format!("Failed to subscribe: {}", e));
                            // Fall back to fetching messages
                            if let Err(e) = app.fetch_messages().await {
                                app.set_status_message(format!("Failed to fetch messages: {}", e));
                            }
                        }
                    }
                }
            }
        }
        Panel::VersionControl => {
            match app.vc_focus {
                VcFocus::FileList => {
                    // Select file and fetch diff
                    if !app.files.is_empty() {
                        if let Err(e) = app.fetch_selected_file_diff().await {
                            app.set_status_message(format!("Failed to fetch diff: {}", e));
                        }
                    }
                }
                VcFocus::Terminal => {
                    // Run command (handled in handle_terminal_input)
                }
                VcFocus::Diff => {
                    // Could add scrolling or other diff interactions
                }
            }
        }
        _ => {}
    }
}

/// Handle new action.
async fn handle_new(app: &mut App, is_worktree: bool) {
    if app.active_panel == Panel::Sidebar {
        match app.create_session(None, is_worktree).await {
            Ok(()) => {
                // Subscribe to the new session for real-time updates
                if let Some(session_id) = app.selected_session_id.clone() {
                    match app.subscribe_to_session(&session_id).await {
                        Ok(()) => {
                            let msg = if is_worktree {
                                "Worktree session created"
                            } else {
                                "Session created"
                            };
                            app.set_status_message(msg.to_string());
                        }
                        Err(e) => {
                            app.set_status_message(format!(
                                "Session created but failed to subscribe: {}",
                                e
                            ));
                        }
                    }
                } else {
                    let msg = if is_worktree {
                        "Worktree session created"
                    } else {
                        "Session created"
                    };
                    app.set_status_message(msg.to_string());
                }
            }
            Err(e) => {
                app.set_status_message(format!("Failed to create session: {}", e));
            }
        }
    }
}

/// Auto-subscribe to the currently selected sidebar session.
/// Called after sidebar_up() / sidebar_down() to load the session immediately.
async fn auto_subscribe_sidebar_session(app: &mut App) {
    if let Some(session_id) = app.selected_session_id.clone() {
        let needs_refresh = app.switch_session(&session_id);

        // Check if this session already has an active subscription
        let has_subscription = app.subscription.is_some();

        if !has_subscription {
            // Not yet subscribed — subscribe and fetch messages
            if let Err(e) = app.subscribe_to_session(&session_id).await {
                app.set_status_message(format!("Failed to subscribe: {}", e));
            }
        } else if needs_refresh {
            // Has subscription but needs a message refresh (e.g. background events arrived)
            let _ = app.fetch_messages().await;
        }
    }
}

/// Handle delete action.
async fn handle_delete(app: &mut App) {
    if app.active_panel == Panel::Sidebar && app.selected_session_id.is_some() {
        match app.delete_session().await {
            Ok(()) => {
                app.set_status_message("Session deleted".to_string());
            }
            Err(e) => {
                app.set_status_message(format!("Failed to delete session: {}", e));
            }
        }
    }
}
