//! Main render function and layout for the TUI.

use super::app::{App, Panel};
use super::components::{account_dialog, chat_panel, sidebar, version_control};
use super::theme::Theme;
use ratatui::{
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::Style,
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph, Widget},
    Frame,
};

/// Render the entire application.
pub fn render(frame: &mut Frame, app: &mut App) {
    let area = frame.area();
    let theme = &app.theme;

    // Clear and fill background with theme color
    Clear.render(area, frame.buffer_mut());
    Block::default()
        .style(Style::default().bg(theme.bg))
        .render(area, frame.buffer_mut());

    // Create main layout: status bar at bottom, main content above
    let main_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(1), Constraint::Length(1)])
        .split(area);

    // Create layout based on whether a session is selected
    let has_session = app.selected_session_id.is_some();

    if has_session {
        // Three-panel layout: Sidebar | Chat | Version Control
        let chunks = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Min(25),        // Sidebar
                Constraint::Percentage(50), // Chat
                Constraint::Min(30),        // Version Control
            ])
            .split(main_chunks[0]);

        sidebar::render(frame, app, chunks[0]);
        chat_panel::render(frame, app, chunks[1]);
        version_control::render(frame, app, chunks[2]);
    } else {
        // Two-panel layout: Sidebar | Empty State
        let chunks = Layout::default()
            .direction(Direction::Horizontal)
            .constraints([
                Constraint::Min(25),         // Sidebar
                Constraint::Percentage(100), // Main content area
            ])
            .split(main_chunks[0]);

        sidebar::render(frame, app, chunks[0]);
        render_empty_state(frame, chunks[1], theme);
    }

    // Render status bar
    render_status_bar(frame, app, main_chunks[1]);

    // Render account dialog overlay (on top of everything)
    account_dialog::render(frame, app);
}

/// Render empty state when no session is selected.
fn render_empty_state(frame: &mut Frame, area: Rect, theme: &Theme) {
    let block = Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.border))
        .style(Style::default().bg(theme.bg_panel));

    let inner = block.inner(area);
    frame.render_widget(block, area);

    // Center the message vertically and horizontally
    let vertical = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage(45),
            Constraint::Length(1),
            Constraint::Percentage(45),
        ])
        .split(inner);

    let message = Paragraph::new(Line::from(Span::styled(
        "Select a session to proceed",
        Style::default().fg(theme.text_muted),
    )))
    .alignment(Alignment::Center);

    frame.render_widget(message, vertical[1]);
}

/// Render the status bar at the bottom.
fn render_status_bar(frame: &mut Frame, app: &App, area: Rect) {
    let theme = &app.theme;
    let status_text = if let Some(msg) = &app.status_message {
        msg.clone()
    } else {
        build_status_text(app)
    };

    let status = Paragraph::new(Line::from(vec![
        Span::styled(" ", Style::default()),
        Span::styled(
            status_text,
            Style::default().fg(if app.status_message.is_some() {
                theme.warning
            } else {
                theme.text_muted
            }),
        ),
    ]))
    .style(Style::default().bg(theme.bg_panel));

    frame.render_widget(status, area);
}

/// Build the default status text.
fn build_status_text(app: &App) -> String {
    let daemon_status = if app.daemon_connected {
        "Connected"
    } else {
        "Disconnected"
    };

    let auth_status = if app.auth_status.authenticated {
        app.auth_status
            .user_email
            .as_deref()
            .or_else(|| {
                app.auth_status
                    .user_id
                    .as_deref()
                    .map(|id| if id.len() > 8 { &id[..8] } else { id })
            })
            .unwrap_or("Authenticated")
    } else {
        "Session expired"
    };

    let panel_name = match app.active_panel {
        Panel::Sidebar => "Sidebar",
        Panel::Chat => "Chat",
        Panel::VersionControl => "Version Control",
    };

    format!(
        "Daemon: {} | Auth: {} | Panel: {} | Press ? for help, q to quit",
        daemon_status, auth_status, panel_name
    )
}

/// Helper to create a styled block for panels.
pub fn panel_block<'a>(title: &str, is_active: bool, theme: &Theme) -> Block<'a> {
    let border_color = if is_active {
        theme.border_active
    } else {
        theme.border
    };

    let title_color = if is_active {
        theme.accent
    } else {
        theme.text_secondary
    };

    Block::default()
        .borders(Borders::ALL)
        .border_style(Style::default().fg(border_color))
        .title(format!(" {} ", title))
        .title_style(Style::default().fg(title_color))
        .style(Style::default().bg(theme.bg_panel))
}

/// Helper to truncate a string to fit within a given width.
pub fn truncate_str(s: &str, max_width: usize) -> String {
    if s.len() <= max_width {
        s.to_string()
    } else if max_width > 3 {
        format!("{}...", &s[..max_width - 3])
    } else {
        s[..max_width].to_string()
    }
}
