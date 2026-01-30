//! Typed Rust structs for Claude Code JSON stream events.
//!
//! These types match the TypeScript Zod schema used by Claude Code.
//! They are used by the TUI to parse raw JSON from ClaudeEvent.

use serde::{Deserialize, Serialize};

/// Top-level Claude message discriminated by `type` field.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClaudeCodeMessage {
    System(SystemMessage),
    Assistant(AssistantMessage),
    User(UserMessage),
    Result(ResultMessage),
    StreamEvent(StreamEventMessage),
}

/// System message containing session metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemMessage {
    pub subtype: Option<String>,
    pub session_id: Option<String>,
    pub tools: Option<Vec<ToolInfo>>,
    pub mcp_servers: Option<Vec<McpServerInfo>>,
    pub model: Option<String>,
    pub cwd: Option<String>,
}

/// Tool information from system message.
/// Can be either a simple string or a detailed object.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum ToolInfo {
    /// Simple string format: "Task", "Bash", etc.
    Simple(String),
    /// Detailed object format: { "name": "Task", "type": "builtin" }
    Detailed {
        name: String,
        #[serde(rename = "type")]
        tool_type: Option<String>,
    },
}

impl ToolInfo {
    /// Get the tool name regardless of format.
    pub fn name(&self) -> &str {
        match self {
            ToolInfo::Simple(name) => name,
            ToolInfo::Detailed { name, .. } => name,
        }
    }
}

/// MCP server information from system message.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpServerInfo {
    pub name: String,
    pub status: String,
}

/// Assistant message containing Claude's response.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssistantMessage {
    pub message: MessageContent,
}

/// User message containing tool results.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserMessage {
    pub message: MessageContent,
}

/// Result message indicating completion.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResultMessage {
    pub subtype: Option<String>,
    pub is_error: Option<bool>,
    pub result: Option<String>,
    pub duration_ms: Option<u64>,
    pub duration_api_ms: Option<u64>,
    pub num_turns: Option<u32>,
    pub session_id: Option<String>,
    pub cost_usd: Option<f64>,
    pub usage: Option<Usage>,
}

/// Token usage information.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Usage {
    pub input_tokens: Option<u64>,
    pub output_tokens: Option<u64>,
    pub cache_creation_input_tokens: Option<u64>,
    pub cache_read_input_tokens: Option<u64>,
}

/// Message content wrapper with blocks.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageContent {
    pub id: Option<String>,
    pub role: Option<String>,
    pub content: Vec<ContentBlock>,
    pub model: Option<String>,
    pub stop_reason: Option<String>,
    pub stop_sequence: Option<String>,
}

/// Content block discriminated by `type` field.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ContentBlock {
    Text(TextBlock),
    ToolUse(ToolUseBlock),
    ToolResult(ToolResultBlock),
}

/// Text content block.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextBlock {
    pub text: String,
}

/// Tool use content block.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolUseBlock {
    pub id: String,
    pub name: String,
    pub input: serde_json::Value,
}

/// Tool result content block.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolResultBlock {
    pub tool_use_id: String,
    #[serde(default)]
    pub is_error: bool,
    pub content: Option<serde_json::Value>,
}

/// Stream event message for real-time content deltas.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamEventMessage {
    pub event: StreamEvent,
}

/// Stream event types.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum StreamEvent {
    ContentBlockDelta { delta: ContentDelta, index: Option<u32> },
    ContentBlockStart { index: u32, content_block: Option<ContentBlock> },
    ContentBlockStop { index: u32 },
    MessageStart { message: Option<serde_json::Value> },
    MessageDelta { delta: Option<serde_json::Value>, usage: Option<Usage> },
    MessageStop,
    #[serde(other)]
    Unknown,
}

/// Content delta types for streaming.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ContentDelta {
    TextDelta { text: String },
    InputJsonDelta { partial_json: String },
    #[serde(other)]
    Unknown,
}

impl ClaudeCodeMessage {
    /// Parse a raw JSON string into a ClaudeCodeMessage.
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }

    /// Get the event type as a string.
    pub fn event_type(&self) -> &'static str {
        match self {
            Self::System(_) => "system",
            Self::Assistant(_) => "assistant",
            Self::User(_) => "user",
            Self::Result(_) => "result",
            Self::StreamEvent(_) => "stream_event",
        }
    }
}

impl AssistantMessage {
    /// Extract all text content concatenated.
    pub fn full_text(&self) -> String {
        self.message
            .content
            .iter()
            .filter_map(|block| match block {
                ContentBlock::Text(t) => Some(t.text.as_str()),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join("")
    }

    /// Get all tool use blocks.
    pub fn tool_uses(&self) -> Vec<&ToolUseBlock> {
        self.message
            .content
            .iter()
            .filter_map(|block| match block {
                ContentBlock::ToolUse(t) => Some(t),
                _ => None,
            })
            .collect()
    }

    /// Check if this message contains any tool use.
    pub fn has_tool_use(&self) -> bool {
        self.message.content.iter().any(|b| matches!(b, ContentBlock::ToolUse(_)))
    }
}

impl UserMessage {
    /// Get all tool result blocks.
    pub fn tool_results(&self) -> Vec<&ToolResultBlock> {
        self.message
            .content
            .iter()
            .filter_map(|block| match block {
                ContentBlock::ToolResult(t) => Some(t),
                _ => None,
            })
            .collect()
    }
}

/// AskUserQuestion input structure (for prompts).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AskUserQuestionInput {
    pub questions: Vec<Question>,
}

/// A single question in AskUserQuestion.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Question {
    pub question: String,
    pub header: Option<String>,
    pub options: Vec<QuestionOption>,
    #[serde(default)]
    pub multi_select: bool,
}

/// An option for a question.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuestionOption {
    pub label: String,
    pub description: Option<String>,
}

/// Task tool input for sub-agents.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskInput {
    pub prompt: String,
    pub subagent_type: String,
    pub description: Option<String>,
    pub model: Option<String>,
}

impl ToolUseBlock {
    /// Check if this is a Task tool (sub-agent).
    pub fn is_task(&self) -> bool {
        self.name == "Task"
    }

    /// Check if this is an AskUserQuestion tool (prompt).
    pub fn is_ask_user_question(&self) -> bool {
        self.name == "AskUserQuestion"
    }

    /// Try to parse input as AskUserQuestion.
    pub fn as_ask_user_question(&self) -> Option<AskUserQuestionInput> {
        if self.is_ask_user_question() {
            serde_json::from_value(self.input.clone()).ok()
        } else {
            None
        }
    }

    /// Try to parse input as Task (sub-agent).
    pub fn as_task(&self) -> Option<TaskInput> {
        if self.is_task() {
            serde_json::from_value(self.input.clone()).ok()
        } else {
            None
        }
    }

    /// Get a preview string for the tool input.
    pub fn input_preview(&self) -> Option<String> {
        match self.name.as_str() {
            "Read" | "Write" => self.input.get("file_path")
                .and_then(|v| v.as_str())
                .map(|s| truncate_path(s, 40)),
            "Bash" => self.input.get("command")
                .and_then(|v| v.as_str())
                .map(|s| truncate_str(s, 50)),
            "Glob" | "Grep" => self.input.get("pattern")
                .and_then(|v| v.as_str())
                .map(String::from),
            "Edit" => self.input.get("file_path")
                .and_then(|v| v.as_str())
                .map(|s| truncate_path(s, 40)),
            "Task" => self.input.get("description")
                .and_then(|v| v.as_str())
                .map(|s| truncate_str(s, 40)),
            "WebFetch" | "WebSearch" => self.input.get("url")
                .or_else(|| self.input.get("query"))
                .and_then(|v| v.as_str())
                .map(|s| truncate_str(s, 40)),
            _ => None,
        }
    }
}

/// Truncate a file path, keeping the filename visible.
fn truncate_path(path: &str, max_len: usize) -> String {
    if path.len() <= max_len {
        return path.to_string();
    }

    // Try to keep the filename
    if let Some(idx) = path.rfind('/') {
        let filename = &path[idx..];
        if filename.len() < max_len - 3 {
            let prefix_len = max_len - filename.len() - 3;
            return format!("...{}{}", &path[..prefix_len], filename);
        }
    }

    // Just truncate from the end
    format!("...{}", &path[path.len() - max_len + 3..])
}

/// Truncate a string, adding ellipsis if needed.
fn truncate_str(s: &str, max_len: usize) -> String {
    if s.len() <= max_len {
        s.to_string()
    } else {
        format!("{}...", &s[..max_len - 3])
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_system_message() {
        let json = r#"{"type":"system","subtype":"init","session_id":"abc123","model":"claude-3-opus"}"#;
        let msg = ClaudeCodeMessage::from_json(json).unwrap();
        match msg {
            ClaudeCodeMessage::System(s) => {
                assert_eq!(s.subtype, Some("init".to_string()));
                assert_eq!(s.session_id, Some("abc123".to_string()));
                assert_eq!(s.model, Some("claude-3-opus".to_string()));
            }
            _ => panic!("Expected System message"),
        }
    }

    #[test]
    fn test_parse_system_message_with_simple_tools() {
        // Claude Code sends tools as simple string array
        let json = r#"{"type":"system","subtype":"init","session_id":"abc123","tools":["Task","Bash","Read","Write"]}"#;
        let msg = ClaudeCodeMessage::from_json(json).unwrap();
        match msg {
            ClaudeCodeMessage::System(s) => {
                assert_eq!(s.subtype, Some("init".to_string()));
                let tools = s.tools.unwrap();
                assert_eq!(tools.len(), 4);
                assert_eq!(tools[0].name(), "Task");
                assert_eq!(tools[1].name(), "Bash");
                assert_eq!(tools[2].name(), "Read");
                assert_eq!(tools[3].name(), "Write");
            }
            _ => panic!("Expected System message"),
        }
    }

    #[test]
    fn test_parse_system_message_with_detailed_tools() {
        // Also support detailed object format
        let json = r#"{"type":"system","subtype":"init","session_id":"abc123","tools":[{"name":"Task","type":"builtin"},{"name":"Bash","type":"builtin"}]}"#;
        let msg = ClaudeCodeMessage::from_json(json).unwrap();
        match msg {
            ClaudeCodeMessage::System(s) => {
                let tools = s.tools.unwrap();
                assert_eq!(tools.len(), 2);
                assert_eq!(tools[0].name(), "Task");
                assert_eq!(tools[1].name(), "Bash");
            }
            _ => panic!("Expected System message"),
        }
    }

    #[test]
    fn test_parse_assistant_message_with_text() {
        let json = r#"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello world"}]}}"#;
        let msg = ClaudeCodeMessage::from_json(json).unwrap();
        match msg {
            ClaudeCodeMessage::Assistant(a) => {
                assert_eq!(a.full_text(), "Hello world");
                assert!(!a.has_tool_use());
            }
            _ => panic!("Expected Assistant message"),
        }
    }

    #[test]
    fn test_parse_assistant_message_with_tool_use() {
        let json = r#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_1","name":"Read","input":{"file_path":"/test.txt"}}]}}"#;
        let msg = ClaudeCodeMessage::from_json(json).unwrap();
        match msg {
            ClaudeCodeMessage::Assistant(a) => {
                assert!(a.has_tool_use());
                let tools = a.tool_uses();
                assert_eq!(tools.len(), 1);
                assert_eq!(tools[0].name, "Read");
                assert_eq!(tools[0].id, "tu_1");
            }
            _ => panic!("Expected Assistant message"),
        }
    }

    #[test]
    fn test_parse_user_message_with_tool_result() {
        let json = r#"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","is_error":false}]}}"#;
        let msg = ClaudeCodeMessage::from_json(json).unwrap();
        match msg {
            ClaudeCodeMessage::User(u) => {
                let results = u.tool_results();
                assert_eq!(results.len(), 1);
                assert_eq!(results[0].tool_use_id, "tu_1");
                assert!(!results[0].is_error);
            }
            _ => panic!("Expected User message"),
        }
    }

    #[test]
    fn test_parse_result_message() {
        let json = r#"{"type":"result","subtype":"success","is_error":false,"duration_ms":1234,"cost_usd":0.01}"#;
        let msg = ClaudeCodeMessage::from_json(json).unwrap();
        match msg {
            ClaudeCodeMessage::Result(r) => {
                assert_eq!(r.subtype, Some("success".to_string()));
                assert_eq!(r.is_error, Some(false));
                assert_eq!(r.duration_ms, Some(1234));
                assert_eq!(r.cost_usd, Some(0.01));
            }
            _ => panic!("Expected Result message"),
        }
    }

    #[test]
    fn test_ask_user_question_parsing() {
        let json = r#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_1","name":"AskUserQuestion","input":{"questions":[{"question":"Which option?","options":[{"label":"A"},{"label":"B"}]}]}}]}}"#;
        let msg = ClaudeCodeMessage::from_json(json).unwrap();
        match msg {
            ClaudeCodeMessage::Assistant(a) => {
                let tools = a.tool_uses();
                assert!(tools[0].is_ask_user_question());
                let q = tools[0].as_ask_user_question().unwrap();
                assert_eq!(q.questions.len(), 1);
                assert_eq!(q.questions[0].question, "Which option?");
                assert_eq!(q.questions[0].options.len(), 2);
            }
            _ => panic!("Expected Assistant message"),
        }
    }

    #[test]
    fn test_task_subagent_parsing() {
        let json = r#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"tu_1","name":"Task","input":{"prompt":"Do something","subagent_type":"Explore","description":"Finding files"}}]}}"#;
        let msg = ClaudeCodeMessage::from_json(json).unwrap();
        match msg {
            ClaudeCodeMessage::Assistant(a) => {
                let tools = a.tool_uses();
                assert!(tools[0].is_task());
                let t = tools[0].as_task().unwrap();
                assert_eq!(t.subagent_type, "Explore");
                assert_eq!(t.description, Some("Finding files".to_string()));
            }
            _ => panic!("Expected Assistant message"),
        }
    }

    #[test]
    fn test_parse_stream_event() {
        let json = r#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"},"index":0}}"#;
        let msg = ClaudeCodeMessage::from_json(json).unwrap();
        match msg {
            ClaudeCodeMessage::StreamEvent(s) => {
                match s.event {
                    StreamEvent::ContentBlockDelta { delta, index } => {
                        assert_eq!(index, Some(0));
                        match delta {
                            ContentDelta::TextDelta { text } => assert_eq!(text, "Hello"),
                            _ => panic!("Expected TextDelta"),
                        }
                    }
                    _ => panic!("Expected ContentBlockDelta"),
                }
            }
            _ => panic!("Expected StreamEvent message"),
        }
    }

    #[test]
    fn test_tool_input_preview() {
        let json = r#"{"type":"tool_use","id":"tu_1","name":"Read","input":{"file_path":"/very/long/path/to/some/deeply/nested/file.rs"}}"#;
        let tool: ToolUseBlock = serde_json::from_str(json).unwrap();
        let preview = tool.input_preview().unwrap();
        assert!(preview.len() <= 43); // 40 + "..."
        assert!(preview.contains("file.rs")); // Should keep filename
    }
}
