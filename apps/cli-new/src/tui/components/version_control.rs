//! Version control panel showing files, diff, and terminal output.

use crate::tui::app::{App, FileStatus, Panel, VcFocus, VcTab};
use crate::tui::theme::Theme;
use crate::tui::ui::{panel_block, truncate_str};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, Paragraph, Tabs, Wrap},
    Frame,
};

/// Render the version control panel.
pub fn render(frame: &mut Frame, app: &App, area: Rect) {
    let is_active = app.active_panel == Panel::VersionControl;
    let theme = &app.theme;
    let block = panel_block("Version Control", is_active, theme);

    // Split into tabs, file list, diff viewer, and terminal
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(2), // Tabs
            Constraint::Min(8),    // File list
            Constraint::Min(6),    // Diff viewer
            Constraint::Min(4),    // Terminal output
        ])
        .split(block.inner(area));

    // Render the outer block
    frame.render_widget(block, area);

    // Render tabs
    render_tabs(frame, app, chunks[0], is_active, theme);

    // Render file list
    render_file_list(frame, app, chunks[1], is_active, theme);

    // Render diff viewer
    render_diff_viewer(frame, app, chunks[2], theme);

    // Render terminal output
    render_terminal(frame, app, chunks[3], theme);
}

/// Render the tab bar.
fn render_tabs(frame: &mut Frame, app: &App, area: Rect, is_active: bool, theme: &Theme) {
    // Include branch name in the tab bar if available
    let branch_info = app.git_branch.as_ref().map(|b| format!(" ({})", b)).unwrap_or_default();
    let titles = vec![format!("Changes{}", branch_info), "All Files".to_string()];
    let selected = match app.vc_tab {
        VcTab::Changes => 0,
        VcTab::AllFiles => 1,
    };

    let highlight_style = if is_active {
        Style::default()
            .fg(theme.accent)
            .bg(theme.bg_panel)
            .add_modifier(Modifier::BOLD)
    } else {
        Style::default().fg(theme.text).bg(theme.bg_panel)
    };

    let tabs = Tabs::new(titles)
        .select(selected)
        .style(Style::default().fg(theme.text_muted).bg(theme.bg_panel))
        .highlight_style(highlight_style)
        .divider("|");

    frame.render_widget(tabs, area);
}

/// Render the file list.
fn render_file_list(frame: &mut Frame, app: &App, area: Rect, is_active: bool, theme: &Theme) {
    let max_width = area.width as usize - 4;

    let items: Vec<ListItem> = app
        .files
        .iter()
        .enumerate()
        .map(|(idx, file)| {
            let is_selected = is_active && idx == app.selected_file_idx;

            let status_color = match file.status {
                FileStatus::Modified => theme.warning,
                FileStatus::Added => theme.success,
                FileStatus::Deleted => theme.error,
                FileStatus::Renamed => theme.info,
                FileStatus::Untracked => theme.text_secondary,
                FileStatus::Conflicted => theme.error,
                FileStatus::Unchanged => theme.text_muted,
            };

            let path = truncate_str(&file.path, max_width.saturating_sub(4));

            let style = if is_selected {
                Style::default()
                    .bg(theme.bg_selection)
                    .add_modifier(Modifier::BOLD)
            } else {
                Style::default()
            };

            // Show staged indicator
            let staged_indicator = if file.staged { "+" } else { " " };

            ListItem::new(Line::from(vec![
                Span::styled(
                    format!("{}{} ", staged_indicator, file.status.display_char()),
                    Style::default().fg(status_color),
                ),
                Span::styled(path, style.fg(theme.text)),
            ]))
        })
        .collect();

    let file_count = app.files.len();
    let title = format!(
        "Files ({}) - {}",
        file_count,
        match app.vc_tab {
            VcTab::Changes => "changes",
            VcTab::AllFiles => "all",
        }
    );

    let list = List::new(items)
        .block(
            Block::default()
                .borders(Borders::TOP)
                .border_style(Style::default().fg(theme.border))
                .title(title)
                .style(Style::default().bg(theme.bg_panel)),
        )
        .style(Style::default().bg(theme.bg_panel));

    frame.render_widget(list, area);
}

/// Render the diff viewer with syntax coloring.
fn render_diff_viewer(frame: &mut Frame, app: &App, area: Rect, theme: &Theme) {
    let title = if let Some(file) = app.files.get(app.selected_file_idx) {
        if app.diff_additions > 0 || app.diff_deletions > 0 {
            format!("Diff: {} (+{} -{}) ", file.path, app.diff_additions, app.diff_deletions)
        } else {
            format!("Diff: {}", file.path)
        }
    } else {
        "Diff".to_string()
    };

    let lines: Vec<Line> = if app.files.is_empty() {
        vec![Line::from(Span::styled(
            "No files to show",
            Style::default().fg(theme.text_muted),
        ))]
    } else if let Some(diff_content) = &app.selected_file_diff {
        diff_content
            .lines()
            .map(|line| {
                let (style, content) = if line.starts_with('+') && !line.starts_with("+++") {
                    (Style::default().fg(theme.success), line)
                } else if line.starts_with('-') && !line.starts_with("---") {
                    (Style::default().fg(theme.error), line)
                } else if line.starts_with("@@") {
                    (Style::default().fg(theme.info).add_modifier(Modifier::BOLD), line)
                } else if line.starts_with("diff ") || line.starts_with("index ") {
                    (Style::default().fg(theme.text_muted), line)
                } else if line.starts_with("---") || line.starts_with("+++") {
                    (Style::default().fg(theme.text_secondary).add_modifier(Modifier::BOLD), line)
                } else {
                    (Style::default().fg(theme.text), line)
                };
                Line::from(Span::styled(content.to_string(), style))
            })
            .collect()
    } else if let Some(file) = app.files.get(app.selected_file_idx) {
        vec![Line::from(Span::styled(
            format!("Select file to view diff: {}", file.path),
            Style::default().fg(theme.text_muted),
        ))]
    } else {
        vec![Line::from(Span::styled(
            "No file selected",
            Style::default().fg(theme.text_muted),
        ))]
    };

    let paragraph = Paragraph::new(lines)
        .style(Style::default().bg(theme.bg_panel))
        .block(
            Block::default()
                .borders(Borders::TOP)
                .border_style(Style::default().fg(theme.border))
                .title(title)
                .style(Style::default().bg(theme.bg_panel)),
        )
        .wrap(Wrap { trim: false });

    frame.render_widget(paragraph, area);
}

/// Render the terminal output.
fn render_terminal(frame: &mut Frame, app: &App, area: Rect, theme: &Theme) {
    let title = if app.terminal_running {
        "Terminal (running...)".to_string()
    } else if let Some(code) = app.terminal_exit_code {
        format!("Terminal (exit: {})", code)
    } else {
        "Terminal".to_string()
    };

    let lines: Vec<Line> = if app.terminal_output.is_empty() {
        vec![Line::from(Span::styled(
            "$ Enter command and press Enter to run",
            Style::default().fg(theme.text_muted),
        ))]
    } else {
        app.terminal_output
            .iter()
            .map(|line| {
                // Color stderr lines differently (they start with a marker in our implementation)
                let style = Style::default().fg(theme.text);
                Line::from(Span::styled(line.clone(), style))
            })
            .collect()
    };

    // Add input line if not running
    let mut all_lines = lines;
    if !app.terminal_running {
        // Only blink cursor when terminal is focused
        let is_terminal_focused =
            app.active_panel == Panel::VersionControl && app.vc_focus == VcFocus::Terminal;

        let cursor_style = if is_terminal_focused {
            Style::default()
                .fg(theme.text)
                .add_modifier(Modifier::SLOW_BLINK)
        } else {
            Style::default().fg(theme.text_muted) // Dimmed, no blink when unfocused
        };

        all_lines.push(Line::from(vec![
            Span::styled("$ ", Style::default().fg(theme.accent)),
            Span::styled(&app.terminal_input, Style::default().fg(theme.text)),
            Span::styled("_", cursor_style),
        ]));
    }

    let paragraph = Paragraph::new(all_lines)
        .style(Style::default().bg(theme.bg_panel))
        .block(
            Block::default()
                .borders(Borders::TOP)
                .border_style(Style::default().fg(theme.border))
                .title(title)
                .style(Style::default().bg(theme.bg_panel)),
        )
        .wrap(Wrap { trim: false });

    frame.render_widget(paragraph, area);
}
