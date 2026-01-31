//! Sidebar component showing repositories and sessions.

use crate::tui::app::{App, Panel};
use crate::tui::theme::Theme;
use crate::tui::ui::{panel_block, truncate_str};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{List, ListItem, Paragraph},
    Frame,
};

/// Render the sidebar panel.
pub fn render(frame: &mut Frame, app: &App, area: Rect) {
    let is_active = app.active_panel == Panel::Sidebar;
    let theme = &app.theme;
    let block = panel_block("Agents", is_active, theme);

    // Split into main content and footer
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(1), Constraint::Length(2)])
        .split(area);

    // Build the list items
    let items = build_sidebar_items(app, chunks[0].width as usize - 4, theme);

    let list = List::new(items)
        .block(block)
        .style(Style::default().bg(theme.bg_panel))
        .highlight_style(
            Style::default()
                .bg(theme.bg_selection)
                .add_modifier(Modifier::BOLD),
        );

    frame.render_widget(list, chunks[0]);

    // Render footer
    render_footer(frame, app, chunks[1], is_active, theme);
}

/// Build the sidebar list items.
fn build_sidebar_items(app: &App, max_width: usize, theme: &Theme) -> Vec<ListItem<'static>> {
    let mut items = Vec::new();

    for (repo_idx, repo) in app.repositories.iter().enumerate() {
        let is_expanded = app.is_repo_expanded(&repo.id);
        let is_selected = repo_idx == app.selected_repo_idx && app.selected_session_idx == 0;

        // Repository icon and name
        let icon = if is_expanded { "v" } else { ">" };
        let name = truncate_str(&repo.name, max_width.saturating_sub(4));

        let style = if is_selected {
            Style::default()
                .fg(theme.accent)
                .add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(theme.text)
        };

        items.push(ListItem::new(Line::from(vec![
            Span::styled(format!("{} ", icon), Style::default().fg(theme.text_muted)),
            Span::styled(name, style),
        ])));

        // Sessions under this repository
        if is_expanded {
            if let Some(sessions) = app.sessions.get(&repo.id) {
                for (session_idx, session) in sessions.iter().enumerate() {
                    let is_session_selected =
                        repo_idx == app.selected_repo_idx && app.selected_session_idx == session_idx + 1;

                    let title = truncate_str(&session.title, max_width.saturating_sub(6));

                    let style = if is_session_selected {
                        Style::default()
                            .fg(theme.success)
                            .add_modifier(Modifier::BOLD)
                    } else {
                        Style::default().fg(theme.text_secondary)
                    };

                    // Show activity indicator for running sessions
                    let is_running = app.is_session_running(&session.id);
                    let (indicator, indicator_color) = if is_running {
                        ("~ ", theme.spinner)
                    } else {
                        ("> ", theme.text_muted)
                    };

                    // Line 1: indicator + title
                    let mut lines = vec![Line::from(vec![
                        Span::raw("  "),
                        Span::styled(indicator, Style::default().fg(indicator_color)),
                        Span::styled(title, style),
                    ])];

                    // Line 2: last message preview
                    let preview_max = max_width.saturating_sub(8); // Extra indent for preview
                    if let Some(preview) = app.get_session_preview(&session.id, preview_max) {
                        lines.push(Line::from(vec![
                            Span::raw("      "), // 6 spaces: 2 base + 4 extra indent
                            Span::styled(
                                truncate_str(&preview, preview_max),
                                Style::default().fg(theme.text_muted),
                            ),
                        ]));
                    }

                    items.push(ListItem::new(lines));
                }
            }
        }
    }

    // If no repositories, show placeholder
    if items.is_empty() {
        items.push(ListItem::new(Line::from(Span::styled(
            "No repositories",
            Style::default().fg(theme.text_muted),
        ))));
    }

    items
}

/// Render the footer with add repo hint.
fn render_footer(frame: &mut Frame, _app: &App, area: Rect, is_active: bool, theme: &Theme) {
    let footer_style = if is_active {
        Style::default().fg(theme.accent).bg(theme.bg)
    } else {
        Style::default().fg(theme.text_muted).bg(theme.bg)
    };

    let footer = Paragraph::new(Line::from(vec![Span::styled(
        " [n] New  [N] Worktree",
        footer_style,
    )]))
    .style(Style::default().bg(theme.bg));

    frame.render_widget(footer, area);
}
