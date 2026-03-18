use serde_json::Value;

const MAX_SUMMARY_CHARS: usize = 600;

pub fn summarize_agent_run_result(value: &Value) -> Option<String> {
    [
        value.get("result").and_then(Value::as_str),
        value.get("content").and_then(Value::as_str),
        value
            .pointer("/result/content/0/text")
            .and_then(Value::as_str),
        value
            .pointer("/message/content/0/text")
            .and_then(Value::as_str),
    ]
    .into_iter()
    .flatten()
    .find_map(sanitize_summary_text)
}

pub fn summarize_agent_run_event(value: &Value) -> Option<String> {
    match value.get("type").and_then(Value::as_str) {
        Some("result") => return summarize_agent_run_result(value),
        Some("assistant") | None => {
            if let Some(message) = value.get("message") {
                if let Some(summary) = summarize_message_content(message) {
                    return Some(summary);
                }
            }
        }
        _ => return None,
    }

    value
        .get("content")
        .and_then(Value::as_str)
        .and_then(sanitize_summary_text)
}

pub fn summarize_agent_run_excerpt(text: &str) -> Option<String> {
    let mut summary = None;

    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        if let Ok(value) = serde_json::from_str::<Value>(trimmed) {
            summary = summarize_agent_run_event(&value)
                .or_else(|| summarize_agent_run_result(&value))
                .or(summary);
            continue;
        }

        if let Ok(unescaped) = serde_json::from_str::<String>(trimmed) {
            if let Ok(value) = serde_json::from_str::<Value>(&unescaped) {
                summary = summarize_agent_run_event(&value)
                    .or_else(|| summarize_agent_run_result(&value))
                    .or(summary);
                continue;
            }

            if let Some(cleaned) = sanitize_summary_text(&unescaped) {
                summary = Some(cleaned);
                continue;
            }
        }

        if let Some(cleaned) = sanitize_summary_text(trimmed) {
            summary = Some(cleaned);
        }
    }

    summary
}

pub fn summarize_agent_run_text(text: &str) -> Option<String> {
    sanitize_summary_text(text)
}

fn summarize_message_content(message: &Value) -> Option<String> {
    let blocks = message.get("content").and_then(Value::as_array)?;
    let mut summaries = Vec::new();
    let mut asks_user = false;

    for block in blocks {
        match block.get("type").and_then(Value::as_str) {
            Some("text") => {
                if let Some(text) = block.get("text").and_then(Value::as_str) {
                    if let Some(summary) = sanitize_summary_text(text) {
                        summaries.push(summary);
                    }
                }
            }
            Some("tool_use")
                if block.get("name").and_then(Value::as_str) == Some("AskUserQuestion") =>
            {
                asks_user = true;
            }
            _ => {}
        }
    }

    if !summaries.is_empty() {
        return sanitize_summary_text(&summaries.join(" "));
    }

    if asks_user {
        return Some("Waiting for user input".to_string());
    }

    None
}

fn sanitize_summary_text(text: &str) -> Option<String> {
    let mut lines = text
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>();

    if lines.is_empty() {
        return None;
    }

    while lines.len() > 1 && lines.first().is_some_and(|line| line.starts_with('#')) {
        lines.remove(0);
    }

    let collapsed = lines.join(" ");
    let collapsed = collapsed.split_whitespace().collect::<Vec<_>>().join(" ");
    let collapsed = collapsed.trim();

    if collapsed.is_empty()
        || collapsed.starts_with("{\"type\":")
        || collapsed.contains("\\u001b[")
        || collapsed.contains('\u{001b}')
    {
        return None;
    }

    Some(truncate_summary(collapsed, MAX_SUMMARY_CHARS))
}

fn truncate_summary(summary: &str, max_chars: usize) -> String {
    if summary.chars().count() <= max_chars {
        return summary.to_string();
    }

    let truncated = summary
        .chars()
        .take(max_chars.saturating_sub(1))
        .collect::<String>();
    format!("{truncated}…")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn summarize_result_prefers_result_field() {
        let value = json!({
            "type": "result",
            "result": "No tasks assigned. Exiting heartbeat.",
            "usage": { "output_tokens": 8 }
        });

        assert_eq!(
            summarize_agent_run_result(&value),
            Some("No tasks assigned. Exiting heartbeat.".to_string())
        );
    }

    #[test]
    fn summarize_event_extracts_assistant_text_blocks() {
        let value = json!({
            "type": "assistant",
            "message": {
                "content": [
                    { "type": "thinking", "thinking": "skip me" },
                    { "type": "text", "text": "Checked assignments and there is no work." }
                ]
            }
        });

        assert_eq!(
            summarize_agent_run_event(&value),
            Some("Checked assignments and there is no work.".to_string())
        );
    }

    #[test]
    fn summarize_event_ignores_user_prompt_payloads() {
        let value = json!({
            "type": "user",
            "message": {
                "content": [
                    { "type": "text", "text": "Base directory for this skill: /tmp/skill" }
                ]
            }
        });

        assert_eq!(summarize_agent_run_event(&value), None);
    }

    #[test]
    fn summarize_excerpt_skips_tool_results_and_uses_terminal_result() {
        let excerpt = concat!(
            "{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"content\":\"/tmp/raw-output\"}]}}\n",
            "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Checking assignments.\"}]}}\n",
            "{\"type\":\"result\",\"result\":\"No tasks assigned. Exiting heartbeat.\"}"
        );

        assert_eq!(
            summarize_agent_run_excerpt(excerpt),
            Some("No tasks assigned. Exiting heartbeat.".to_string())
        );
    }

    #[test]
    fn sanitize_markdown_heading_prefers_body_copy() {
        let markdown = "## Heartbeat Summary\n\nUpdated issue status to blocked.";

        assert_eq!(
            summarize_agent_run_text(markdown),
            Some("Updated issue status to blocked.".to_string())
        );
    }
}
