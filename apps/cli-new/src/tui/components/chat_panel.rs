//! Chat panel component showing messages and input.

use crate::tui::app::{App, InputMode, MessageRole, Panel, ToolStatus};
use crate::tui::theme::Theme;
use crate::tui::ui::panel_block;
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Wrap},
    Frame,
};
use textwrap::wrap;

/// Render the chat panel.
pub fn render(frame: &mut Frame, app: &App, area: Rect) {
    let is_active = app.active_panel == Panel::Chat;
    let theme = &app.theme;

    // Get selected session title for header
    let title = if let Some(session_id) = &app.selected_session_id {
        if let Some(repo) = app.selected_repo() {
            if let Some(sessions) = app.sessions.get(&repo.id) {
                sessions
                    .iter()
                    .find(|s| &s.id == session_id)
                    .map(|s| format!("Chat - {}", s.title))
                    .unwrap_or_else(|| "Chat".to_string())
            } else {
                "Chat".to_string()
            }
        } else {
            "Chat".to_string()
        }
    } else {
        "Chat".to_string()
    };

    let block = panel_block(&title, is_active, theme);

    // Split into messages area and input area
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(1), Constraint::Length(3)])
        .split(area);

    // Render messages
    render_messages(frame, app, chunks[0], block, theme);

    // Render input
    render_input(frame, app, chunks[1], is_active, theme);
}

/// Render the message list with scrolling support.
fn render_messages(frame: &mut Frame, app: &App, area: Rect, block: Block<'_>, theme: &Theme) {
    // Calculate inner area dimensions (account for borders)
    let inner_height = area.height.saturating_sub(2) as usize;
    let inner_width = area.width.saturating_sub(4) as usize;

    if inner_width == 0 || inner_height == 0 {
        frame.render_widget(block, area);
        return;
    }

    // Check for empty state
    let show_placeholder = app.messages.is_empty()
        && app.streaming_content.is_none()
        && !app.claude_running
        && app.active_tools.is_empty()
        && app.active_sub_agent.is_none()
        && app.pending_prompt.is_none()
        && app.tool_history.is_empty();

    if show_placeholder {
        let placeholder = if app.selected_session_id.is_none() {
            "Select a session to view messages"
        } else {
            "No messages yet. Press 'i' to start typing."
        };

        let paragraph = Paragraph::new(Line::from(Span::styled(
            placeholder,
            Style::default().fg(theme.text_muted),
        )))
        .block(block)
        .style(Style::default().bg(theme.bg_panel))
        .wrap(Wrap { trim: true });

        frame.render_widget(paragraph, area);
        return;
    }

    // Build all lines
    let all_lines = build_all_message_lines(app, inner_width, theme);

    // Calculate scroll offset
    let total_lines = all_lines.len();
    let max_scroll = total_lines.saturating_sub(inner_height);

    let scroll_offset = if app.chat_auto_scroll {
        // Auto-scroll to bottom
        max_scroll as u16
    } else {
        // Clamp manual scroll to valid range
        app.chat_scroll_offset.min(max_scroll as u16)
    };

    // Create paragraph with scroll
    let paragraph = Paragraph::new(all_lines)
        .block(block)
        .style(Style::default().bg(theme.bg_panel))
        .scroll((scroll_offset, 0));

    frame.render_widget(paragraph, area);
}

/// Build all message lines for the chat panel.
/// Tool history is interleaved with messages based on after_message_idx.
fn build_all_message_lines<'a>(app: &App, inner_width: usize, theme: &'a Theme) -> Vec<Line<'a>> {
    let mut lines: Vec<Line> = Vec::new();

    // Add message lines with interleaved tool history
    for (idx, msg) in app.messages.iter().enumerate() {
        // Render the message
        lines.extend(render_single_message(msg, inner_width, theme));

        // Render any tool history that belongs after this message
        for entry in &app.tool_history {
            if entry.after_message_idx == idx {
                lines.push(Line::from(""));
                if let Some(ref sub_agent) = entry.sub_agent {
                    lines.extend(build_sub_agent_lines(sub_agent, theme));
                }
                for tool in &entry.tools {
                    lines.push(build_tool_line(tool, theme, 0));
                }
            }
        }

        if idx < app.messages.len() - 1 {
            lines.push(Line::from(""));
        }
    }

    // Add streaming content
    if let Some(ref streaming_text) = app.streaming_content {
        if !app.messages.is_empty() {
            lines.push(Line::from(""));
        }

        let content_style = Style::default().fg(theme.text);

        // Wrap streaming text to fit width
        let wrapped_lines = wrap(streaming_text, inner_width);

        for (line_idx, line_text) in wrapped_lines.iter().enumerate() {
            let is_last_line = line_idx == wrapped_lines.len() - 1;
            let cursor = if is_last_line { " \u{2588}" } else { "" };

            lines.push(Line::from(vec![
                Span::styled(line_text.to_string(), content_style),
                Span::styled(cursor.to_string(), Style::default().fg(theme.spinner)),
            ]));
        }
    } else if app.claude_running {
        if !app.messages.is_empty() {
            lines.push(Line::from(""));
        }
        let spinner = app.spinner_char();
        lines.push(Line::from(vec![
            Span::styled(format!("{} ", spinner), Style::default().fg(theme.spinner)),
            Span::styled(
                "Claude is thinking...".to_string(),
                Style::default()
                    .fg(theme.spinner)
                    .add_modifier(Modifier::ITALIC),
            ),
        ]));
    }

    // Add currently active sub-agent (running) at the end
    if let Some(ref sub_agent) = app.active_sub_agent {
        lines.push(Line::from(""));
        lines.extend(build_sub_agent_lines(sub_agent, theme));
    }

    // Add currently active tools (running) at the end
    if !app.active_tools.is_empty() && app.active_sub_agent.is_none() {
        lines.push(Line::from(""));
        for tool in &app.active_tools {
            lines.push(build_tool_line(tool, theme, 0));
        }
    }

    // Add prompt lines
    if let Some(ref prompt) = app.pending_prompt {
        lines.push(Line::from(""));
        lines.extend(build_prompt_lines(prompt, theme));
    }

    lines
}

/// Render a single message to lines.
fn render_single_message<'a>(msg: &crate::tui::app::ChatMessage, inner_width: usize, theme: &'a Theme) -> Vec<Line<'a>> {
    let mut lines = Vec::new();

    match msg.role {
        MessageRole::User => {
            // User messages: right-aligned with background, no label
            let text_style = Style::default().fg(theme.text).bg(theme.bg_user_message);

            // Wrap text to fit width with padding (1 space each side)
            let content_width = inner_width.saturating_sub(2);
            let wrapped = wrap(&msg.content, content_width);

            for line_text in wrapped {
                let content = format!(" {} ", line_text); // 1 space padding each side
                let padding = inner_width.saturating_sub(content.len());
                lines.push(Line::from(vec![
                    Span::raw(" ".repeat(padding)),
                    Span::styled(content, text_style),
                ]));
            }
        }
        MessageRole::Assistant => {
            // Assistant messages: left-aligned, no label, markdown rendered
            let md_lines = render_themed_markdown(&msg.content, inner_width, theme);
            lines.extend(md_lines);
        }
        MessageRole::System => {
            // System messages: italic, muted
            let prefix = "System: ";
            let prefix_style = Style::default()
                .fg(theme.system_message)
                .add_modifier(Modifier::BOLD | Modifier::ITALIC);
            let content_style = Style::default()
                .fg(theme.text_muted)
                .add_modifier(Modifier::ITALIC);

            let prefix_len = prefix.len();
            let first_line_width = inner_width.saturating_sub(prefix_len);
            let wrapped_lines = wrap_message_text(&msg.content, first_line_width, inner_width, prefix_len);

            for (line_idx, line_text) in wrapped_lines.iter().enumerate() {
                let line = if line_idx == 0 {
                    Line::from(vec![
                        Span::styled(prefix.to_string(), prefix_style),
                        Span::styled(line_text.to_string(), content_style),
                    ])
                } else {
                    Line::from(vec![
                        Span::styled(" ".repeat(prefix_len), Style::default()),
                        Span::styled(line_text.to_string(), content_style),
                    ])
                };
                lines.push(line);
            }
        }
    }

    lines
}

/// Build a line for a single tool with input preview.
fn build_tool_line<'a>(tool: &crate::tui::app::ActiveTool, theme: &'a Theme, indent: usize) -> Line<'a> {
    let (icon, icon_color) = match tool.status {
        ToolStatus::Running => ("\u{25B6}", theme.spinner),  // ▶
        ToolStatus::Completed => ("\u{2713}", theme.success), // ✓
        ToolStatus::Failed => ("\u{2717}", theme.error),      // ✗
    };

    let indent_str = " ".repeat(indent);

    let mut spans = vec![
        Span::styled(indent_str, Style::default()),
        Span::styled(format!("{} ", icon), Style::default().fg(icon_color)),
        Span::styled(
            tool.tool_name.clone(),
            Style::default().fg(theme.text).add_modifier(Modifier::BOLD),
        ),
    ];

    // Add input preview if available
    if let Some(ref preview) = tool.input_preview {
        spans.push(Span::styled(
            format!(" ({})", preview),
            Style::default().fg(theme.text_muted),
        ));
    }

    Line::from(spans)
}

/// Build lines for a sub-agent with child tools.
fn build_sub_agent_lines<'a>(sub_agent: &crate::tui::app::ActiveSubAgent, theme: &'a Theme) -> Vec<Line<'a>> {
    let mut lines = Vec::new();

    let (icon, icon_color) = match sub_agent.status {
        ToolStatus::Running => ("\u{25C6}", theme.spinner),  // ◆
        ToolStatus::Completed => ("\u{25C7}", theme.success), // ◇
        ToolStatus::Failed => ("\u{25C7}", theme.error),      // ◇
    };

    let description = sub_agent.description.as_deref().unwrap_or("");
    let description_preview = if description.len() > 40 {
        format!("{}...", &description[..40])
    } else {
        description.to_string()
    };

    lines.push(Line::from(vec![
        Span::styled(format!("{} ", icon), Style::default().fg(icon_color)),
        Span::styled(
            sub_agent.subagent_type.clone(),
            Style::default().fg(theme.assistant_message).add_modifier(Modifier::BOLD),
        ),
        Span::styled(": ".to_string(), Style::default().fg(theme.text_muted)),
        Span::styled(
            description_preview,
            Style::default().fg(theme.text_muted).add_modifier(Modifier::ITALIC),
        ),
    ]));

    for tool in &sub_agent.child_tools {
        lines.push(build_tool_line(tool, theme, 2));
    }

    lines
}

/// Build lines for a pending prompt.
fn build_prompt_lines<'a>(prompt: &crate::tui::app::PendingPrompt, theme: &'a Theme) -> Vec<Line<'a>> {
    let mut lines = Vec::new();

    lines.push(Line::from(vec![
        Span::styled("? ".to_string(), Style::default().fg(theme.warning).add_modifier(Modifier::BOLD)),
        Span::styled(
            prompt.question.clone(),
            Style::default().fg(theme.text).add_modifier(Modifier::BOLD),
        ),
    ]));

    for (idx, option) in prompt.options.iter().enumerate() {
        let is_selected = idx == prompt.selected_option;
        let prefix = if is_selected { "\u{203A} " } else { "  " }; // ›
        let style = if is_selected {
            Style::default().fg(theme.success).add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(theme.text)
        };

        let mut spans = vec![
            Span::styled(prefix.to_string(), style),
            Span::styled(format!("{}. ", idx + 1), Style::default().fg(theme.text_muted)),
            Span::styled(option.label.clone(), style),
        ];

        if let Some(ref desc) = option.description {
            spans.push(Span::styled(" - ".to_string(), Style::default().fg(theme.text_muted)));
            spans.push(Span::styled(
                desc.clone(),
                Style::default().fg(theme.text_muted).add_modifier(Modifier::ITALIC),
            ));
        }

        lines.push(Line::from(spans));
    }

    lines.push(Line::from(vec![
        Span::styled(
            "  [\u{2191}/\u{2193} or 1-9 to select, Enter to confirm]".to_string(),
            Style::default().fg(theme.text_muted).add_modifier(Modifier::ITALIC),
        ),
    ]));

    lines
}

/// Wrap message text with support for different first-line and continuation widths.
fn wrap_message_text(
    text: &str,
    first_line_width: usize,
    continuation_width: usize,
    _continuation_indent: usize,
) -> Vec<String> {
    if text.is_empty() {
        return vec![String::new()];
    }

    let mut result = Vec::new();

    // Wrap first line
    let first_wrapped = wrap(text, first_line_width);
    if first_wrapped.is_empty() {
        return vec![String::new()];
    }

    result.push(first_wrapped[0].to_string());

    // If there's remaining text, wrap with continuation width
    if first_wrapped.len() > 1 {
        // Get the remaining text after the first line
        let first_line_chars: usize = first_wrapped[0].len();
        let remaining = text.chars().skip(first_line_chars).collect::<String>();
        let remaining = remaining.trim_start();

        if !remaining.is_empty() {
            let continuation_wrapped = wrap(remaining, continuation_width);
            for line in continuation_wrapped {
                result.push(line.to_string());
            }
        }
    }

    result
}

/// Render the input area.
fn render_input(frame: &mut Frame, app: &App, area: Rect, is_active: bool, theme: &Theme) {
    let input_style = match app.input_mode {
        InputMode::Normal => Style::default().fg(theme.text_muted).bg(theme.bg_panel),
        InputMode::Editing => Style::default().fg(theme.text).bg(theme.bg_panel),
        InputMode::Prompt => Style::default().fg(theme.warning).bg(theme.bg_panel),
    };

    let border_color = match (is_active, app.input_mode) {
        (_, InputMode::Editing) => theme.success,
        (_, InputMode::Prompt) => theme.warning,
        (true, _) => theme.border_active,
        (false, _) => theme.border,
    };

    let input_text = match app.input_mode {
        InputMode::Prompt => "[Use arrow keys or 1-9 to select, Enter to confirm]".to_string(),
        InputMode::Normal if app.chat_input.is_empty() => "[i] Type a message...".to_string(),
        _ => app.chat_input.clone(),
    };

    let title = match app.input_mode {
        InputMode::Editing => " Editing (Esc to exit) ",
        InputMode::Prompt => " Prompt (Esc to cancel) ",
        InputMode::Normal => " Input ",
    };

    let input = Paragraph::new(input_text)
        .style(input_style)
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(border_color))
                .title(title)
                .style(Style::default().bg(theme.bg_panel)),
        );

    frame.render_widget(input, area);

    // Set cursor position when editing
    if app.input_mode == InputMode::Editing {
        frame.set_cursor_position((area.x + app.chat_input.len() as u16 + 1, area.y + 1));
    }
}

/// Render markdown text with theme-aware colors.
/// Handles code blocks, inline code, bold, italic, headers, and lists.
fn render_themed_markdown<'a>(text: &str, inner_width: usize, theme: &'a Theme) -> Vec<Line<'a>> {
    let mut lines: Vec<Line<'a>> = Vec::new();
    let mut in_code_block = false;
    let mut code_block_lines: Vec<String> = Vec::new();

    for line in text.lines() {
        // Handle fenced code blocks
        if line.trim_start().starts_with("```") {
            if in_code_block {
                // End of code block - render accumulated lines
                for code_line in &code_block_lines {
                    // Truncate code lines that are too long
                    let display_line = if code_line.len() > inner_width.saturating_sub(2) {
                        format!("{}...", &code_line[..inner_width.saturating_sub(5)])
                    } else {
                        code_line.clone()
                    };
                    lines.push(Line::from(vec![Span::styled(
                        format!("  {}", display_line),
                        Style::default().fg(theme.accent).add_modifier(Modifier::DIM),
                    )]));
                }
                code_block_lines.clear();
                in_code_block = false;
            } else {
                // Start of code block
                in_code_block = true;
            }
            continue;
        }

        if in_code_block {
            code_block_lines.push(line.to_string());
            continue;
        }

        // Handle headers
        if line.starts_with('#') {
            let header_level = line.chars().take_while(|&c| c == '#').count();
            let header_text = line[header_level..].trim_start();
            let style = Style::default()
                .fg(theme.assistant_message)
                .add_modifier(Modifier::BOLD);
            // Wrap headers if too long
            let wrapped = wrap(header_text, inner_width);
            for wrapped_line in wrapped {
                lines.push(Line::from(vec![Span::styled(wrapped_line.to_string(), style)]));
            }
            continue;
        }

        // Handle bullet lists
        let trimmed = line.trim_start();
        let indent = line.len() - trimmed.len();
        let indent_str = " ".repeat(indent);

        if trimmed.starts_with("- ") || trimmed.starts_with("* ") {
            let list_content = &trimmed[2..];
            let bullet_style = Style::default().fg(theme.text_muted);
            // Wrap list content (accounting for indent + bullet)
            let list_width = inner_width.saturating_sub(indent + 2);
            let wrapped = wrap(list_content, list_width);
            for (idx, wrapped_line) in wrapped.iter().enumerate() {
                let content_spans = parse_inline_markdown(&wrapped_line, theme);
                let mut spans = vec![Span::raw(indent_str.clone())];
                if idx == 0 {
                    spans.push(Span::styled("• ", bullet_style));
                } else {
                    spans.push(Span::raw("  ")); // continuation indent
                }
                spans.extend(content_spans);
                lines.push(Line::from(spans));
            }
            continue;
        }

        // Handle numbered lists
        if let Some(rest) = parse_numbered_list(trimmed) {
            // Get the prefix (everything before the rest)
            let prefix_len = trimmed.len() - rest.len();
            let num_prefix = &trimmed[..prefix_len];
            // Wrap list content (accounting for indent + number prefix)
            let list_width = inner_width.saturating_sub(indent + prefix_len);
            let wrapped = wrap(rest, list_width);
            for (idx, wrapped_line) in wrapped.iter().enumerate() {
                let content_spans = parse_inline_markdown(&wrapped_line, theme);
                let mut spans = vec![Span::raw(indent_str.clone())];
                if idx == 0 {
                    spans.push(Span::styled(num_prefix.to_string(), Style::default().fg(theme.text_muted)));
                } else {
                    spans.push(Span::raw(" ".repeat(prefix_len))); // continuation indent
                }
                spans.extend(content_spans);
                lines.push(Line::from(spans));
            }
            continue;
        }

        // Regular paragraph - parse inline markdown with wrapping
        if line.is_empty() {
            lines.push(Line::from(""));
        } else {
            let wrapped = wrap(line, inner_width);
            for wrapped_line in wrapped {
                let spans = parse_inline_markdown(&wrapped_line, theme);
                lines.push(Line::from(spans));
            }
        }
    }

    // Handle unclosed code block
    if in_code_block {
        for code_line in &code_block_lines {
            // Truncate code lines that are too long
            let display_line = if code_line.len() > inner_width.saturating_sub(2) {
                format!("{}...", &code_line[..inner_width.saturating_sub(5)])
            } else {
                code_line.clone()
            };
            lines.push(Line::from(vec![Span::styled(
                format!("  {}", display_line),
                Style::default().fg(theme.accent).add_modifier(Modifier::DIM),
            )]));
        }
    }

    lines
}

/// Parse a numbered list line, returning the content after the number.
fn parse_numbered_list(line: &str) -> Option<&str> {
    let mut idx = 0;
    let bytes = line.as_bytes();

    // Must start with a digit
    if idx >= bytes.len() || !bytes[idx].is_ascii_digit() {
        return None;
    }

    // Consume digits
    while idx < bytes.len() && bytes[idx].is_ascii_digit() {
        idx += 1;
    }

    // Must be followed by . or )
    if idx >= bytes.len() || (bytes[idx] != b'.' && bytes[idx] != b')') {
        return None;
    }
    idx += 1;

    // Must be followed by space
    if idx >= bytes.len() || bytes[idx] != b' ' {
        return None;
    }
    idx += 1;

    // Return remaining content
    Some(&line[idx..])
}

/// Parse inline markdown (bold, italic, code) and return styled spans.
fn parse_inline_markdown<'a>(text: &str, theme: &'a Theme) -> Vec<Span<'a>> {
    let mut spans: Vec<Span<'a>> = Vec::new();
    let mut chars = text.chars().peekable();
    let mut current = String::new();

    let text_style = Style::default().fg(theme.text);
    let code_style = Style::default().fg(theme.accent);
    let bold_style = Style::default().fg(theme.text).add_modifier(Modifier::BOLD);
    let italic_style = Style::default().fg(theme.text).add_modifier(Modifier::ITALIC);
    let link_style = Style::default().fg(theme.info).add_modifier(Modifier::UNDERLINED);

    while let Some(ch) = chars.next() {
        match ch {
            // Inline code
            '`' => {
                if !current.is_empty() {
                    spans.push(Span::styled(std::mem::take(&mut current), text_style));
                }
                let mut code = String::new();
                while let Some(&next) = chars.peek() {
                    if next == '`' {
                        chars.next();
                        break;
                    }
                    code.push(chars.next().unwrap());
                }
                spans.push(Span::styled(code, code_style));
            }
            // Bold or italic with **
            '*' => {
                if chars.peek() == Some(&'*') {
                    chars.next(); // consume second *
                    if !current.is_empty() {
                        spans.push(Span::styled(std::mem::take(&mut current), text_style));
                    }
                    let mut bold_text = String::new();
                    while let Some(&next) = chars.peek() {
                        if next == '*' {
                            chars.next();
                            if chars.peek() == Some(&'*') {
                                chars.next();
                                break;
                            }
                            bold_text.push('*');
                        } else {
                            bold_text.push(chars.next().unwrap());
                        }
                    }
                    spans.push(Span::styled(bold_text, bold_style));
                } else {
                    // Single * for italic
                    if !current.is_empty() {
                        spans.push(Span::styled(std::mem::take(&mut current), text_style));
                    }
                    let mut italic_text = String::new();
                    while let Some(&next) = chars.peek() {
                        if next == '*' {
                            chars.next();
                            break;
                        }
                        italic_text.push(chars.next().unwrap());
                    }
                    spans.push(Span::styled(italic_text, italic_style));
                }
            }
            // Links [text](url)
            '[' => {
                if !current.is_empty() {
                    spans.push(Span::styled(std::mem::take(&mut current), text_style));
                }
                let mut link_text = String::new();
                let mut found_close = false;
                while let Some(&next) = chars.peek() {
                    if next == ']' {
                        chars.next();
                        found_close = true;
                        break;
                    }
                    link_text.push(chars.next().unwrap());
                }
                if found_close && chars.peek() == Some(&'(') {
                    chars.next(); // consume (
                    // Skip the URL
                    while let Some(&next) = chars.peek() {
                        if next == ')' {
                            chars.next();
                            break;
                        }
                        chars.next();
                    }
                    spans.push(Span::styled(link_text, link_style));
                } else {
                    // Not a valid link, treat as regular text
                    current.push('[');
                    current.push_str(&link_text);
                    if found_close {
                        current.push(']');
                    }
                }
            }
            _ => {
                current.push(ch);
            }
        }
    }

    if !current.is_empty() {
        spans.push(Span::styled(current, text_style));
    }

    spans
}

