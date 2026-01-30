//! Account dialog component for login/logout.

use crate::tui::app::App;
use crate::tui::theme::Theme;
use ratatui::{
    layout::Rect,
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph},
    Frame,
};

/// Action that can be taken from the account dialog.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DialogAction {
    None,
    Logout,
}

/// Render the account dialog overlay.
pub fn render(frame: &mut Frame, app: &App) {
    if !app.show_account_dialog {
        return;
    }

    let theme = &app.theme;

    // Calculate centered area for dialog
    let area = centered_rect(40, 14, frame.area());

    // Clear the background area
    frame.render_widget(Clear, area);

    // Build dialog content based on auth state
    let block = Block::default()
        .title(" Account ")
        .borders(Borders::ALL)
        .border_style(Style::default().fg(theme.border_active))
        .style(Style::default().bg(theme.bg_panel));

    frame.render_widget(block, area);

    // Inner area for content
    let inner = Rect {
        x: area.x + 2,
        y: area.y + 1,
        width: area.width.saturating_sub(4),
        height: area.height.saturating_sub(2),
    };

    let lines = build_dialog_content(app, theme);
    let paragraph = Paragraph::new(lines);
    frame.render_widget(paragraph, inner);
}

/// Build the dialog content lines based on authentication state.
fn build_dialog_content(app: &App, theme: &Theme) -> Vec<Line<'static>> {
    let mut lines = Vec::new();

    if app.auth_status.authenticated {
        // Logged in state
        lines.push(Line::from(Span::styled(
            "Logged in as:",
            Style::default().fg(theme.text_secondary),
        )));

        let email_display = app
            .auth_status
            .user_email
            .as_deref()
            .unwrap_or("(no email)");
        lines.push(Line::from(Span::styled(
            email_display.to_string(),
            Style::default().fg(theme.accent),
        )));

        lines.push(Line::from(""));

        // User ID (truncated)
        if let Some(ref user_id) = app.auth_status.user_id {
            let truncated_id = if user_id.len() > 12 {
                format!("{}...", &user_id[..12])
            } else {
                user_id.clone()
            };
            lines.push(Line::from(vec![
                Span::styled("User ID: ", Style::default().fg(theme.text_secondary)),
                Span::styled(truncated_id, Style::default().fg(theme.text_muted)),
            ]));
        }

        // Expiration
        if let Some(ref expires_at) = app.auth_status.expires_at {
            // Format the expiration time nicely
            let expires_display = format_expires_at(expires_at);
            lines.push(Line::from(vec![
                Span::styled("Expires: ", Style::default().fg(theme.text_secondary)),
                Span::styled(expires_display, Style::default().fg(theme.text_muted)),
            ]));
        }

        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            "────────────────────────",
            Style::default().fg(theme.border),
        )));
        lines.push(Line::from(""));

        // Logout option
        let logout_style = if app.account_dialog_selected == 0 {
            Style::default()
                .fg(theme.error)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(theme.text)
        };
        let prefix = if app.account_dialog_selected == 0 {
            "> "
        } else {
            "  "
        };
        lines.push(Line::from(Span::styled(
            format!("{}Logout", prefix),
            logout_style,
        )));

        lines.push(Line::from(""));
        lines.push(Line::from(vec![
            Span::styled("[Esc]", Style::default().fg(theme.text_muted)),
            Span::styled(" Close  ", Style::default().fg(theme.text_secondary)),
            Span::styled("[Enter]", Style::default().fg(theme.text_muted)),
            Span::styled(" Select", Style::default().fg(theme.text_secondary)),
        ]));
    } else {
        // Not logged in - this shouldn't happen since TUI requires auth
        lines.push(Line::from(Span::styled(
            "Session expired",
            Style::default().fg(theme.warning),
        )));

        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled(
            "Restart the CLI to login again.",
            Style::default().fg(theme.text_secondary),
        )));

        lines.push(Line::from(""));
        lines.push(Line::from(vec![
            Span::styled("[Esc]", Style::default().fg(theme.text_muted)),
            Span::styled(" Close", Style::default().fg(theme.text_secondary)),
        ]));
    }

    lines
}

/// Get the action for the currently selected option.
pub fn get_selected_action(app: &App) -> DialogAction {
    if !app.show_account_dialog {
        return DialogAction::None;
    }

    // Only logout is available - login happens before TUI starts
    if app.auth_status.authenticated {
        DialogAction::Logout
    } else {
        DialogAction::None
    }
}

/// Format the expires_at timestamp for display.
fn format_expires_at(expires_at: &str) -> String {
    // Try to parse as RFC3339 and format nicely
    if let Ok(dt) = chrono::DateTime::parse_from_rfc3339(expires_at) {
        dt.format("%Y-%m-%d %H:%M").to_string()
    } else {
        // Fallback to showing raw value (truncated)
        if expires_at.len() > 16 {
            format!("{}...", &expires_at[..16])
        } else {
            expires_at.to_string()
        }
    }
}

/// Create a centered rect of given width and height within the parent area.
fn centered_rect(width: u16, height: u16, area: Rect) -> Rect {
    let x = area.x + (area.width.saturating_sub(width)) / 2;
    let y = area.y + (area.height.saturating_sub(height)) / 2;

    Rect {
        x,
        y,
        width: width.min(area.width),
        height: height.min(area.height),
    }
}
