# Deku

Deku is the **Claude CLI process manager** for the Unbound daemon. It encapsulates all the logic for spawning, streaming, and controlling Claude CLI processes.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           Daemon                                 │
│                                                                  │
│  IPC Handler ──► Deku::spawn() ──► ClaudeProcess                │
│                        │                  │                      │
│                        │                  │ stdout               │
│                        │                  ▼                      │
│                        │          ClaudeEventStream              │
│                        │                  │                      │
│                        │                  │ ClaudeEvent          │
│                        │                  ▼                      │
│                        └────────► Event Handler (Armin, IPC)     │
└─────────────────────────────────────────────────────────────────┘
```

## Usage

```rust
use deku::{ClaudeConfig, ClaudeProcess, ClaudeEvent};

// Create configuration
let config = ClaudeConfig::new("Hello, Claude!", "/path/to/repo")
    .with_resume_session("previous-session-id"); // Optional

// Spawn the process
let mut process = ClaudeProcess::spawn(config).await?;

// Get the event stream
let mut stream = process.take_stream().unwrap();

// Process events
while let Some(event) = stream.next().await {
    match event {
        ClaudeEvent::Json { event_type, raw, .. } => {
            println!("Event: {} - {}", event_type, raw);
        }
        ClaudeEvent::SystemWithSessionId { claude_session_id, .. } => {
            println!("Claude session: {}", claude_session_id);
        }
        ClaudeEvent::Result { is_error, .. } => {
            println!("Completed (error={})", is_error);
        }
        ClaudeEvent::Finished { success, .. } => {
            println!("Process finished: {}", success);
            break;
        }
        ClaudeEvent::Stopped => {
            println!("Process was stopped");
            break;
        }
        _ => {}
    }
}
```

## Stopping a Process

```rust
// From the process handle
process.stop();

// Or via the stop sender (can be cloned for use in other tasks)
let stop_tx = process.stop_sender();
tokio::spawn(async move {
    // Later...
    let _ = stop_tx.send(());
});
```

## Event Types

| Event | Description |
|-------|-------------|
| `Json` | Generic JSON event from Claude stdout |
| `SystemWithSessionId` | System event containing Claude session ID |
| `Result` | Completion event (may indicate error) |
| `Stderr` | Line from stderr |
| `Finished` | Process exited normally |
| `Stopped` | Process was stopped via signal |

## Configuration

| Option | Description |
|--------|-------------|
| `message` | The prompt to send to Claude |
| `working_dir` | Working directory for the process |
| `resume_session_id` | Optional Claude session ID to resume |
| `allowed_tools` | Custom tool allowlist (has sensible defaults) |

## Integration

Deku is designed to be integrated with the daemon's event handling:

1. **Daemon spawns** a Claude process via Deku
2. **Event stream** yields parsed JSON events
3. **Handler bridges** events to Armin (storage) and IPC (real-time broadcast)
4. **Stop signal** can be sent from IPC handler when user requests abort
