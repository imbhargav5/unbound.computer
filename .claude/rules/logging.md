# Swift Logging Standards

## Use swift-log Package

All Swift files must use the `swift-log` package for logging. Never use `print()` or `os.log` directly.

## Logger Declaration

Use component-based labels for colored log output:

```swift
import Logging

private let logger = Logger(label: "app.component")
```

## Component Labels

Use hierarchical labels based on the file's purpose:

| Component | Label | Color (dev) | Use For |
|-----------|-------|-------------|---------|
| Network | `app.network` | Cyan | HTTP, push notifications, deep links |
| Database | `app.database` | Green | Database services, repositories |
| Sync | `app.sync` | Yellow | Data synchronization services |
| UI | `app.ui` | Magenta | Views, view models |
| Auth | `app.auth` | Blue | Authentication, device trust |
| Claude | `app.claude` | Bright Magenta | Claude CLI integration |
| JSON | `app.json` | Bright Red | Claude JSON stream parsing |
| Relay | `app.relay` | Bright Cyan | WebSocket relay connections |
| Outbox | `app.outbox` | Bright Yellow | Message queue, pipeline |
| Session | `app.session` | Bright Green | Session management |
| Device | `app.device` | Bright Blue | Device identity, presence |
| Config | `app.config` | Gray | Configuration |
| State | `app.state` | Gray | App state management |

Hierarchical labels supported: `app.network.auth`, `app.ui.chat` (chat panel/view model), `app.relay.session`

## Rules

1. **No print() in production code** - Always use Logger
2. **No direct os.log usage** - Use swift-log which multiplexes to OSLog
3. **Test files may use print()** - Files prefixed with `test_` are exempt
4. **One logger per file** - Declare as `private let` at file scope
5. **No ANSI codes in messages** - Colors are handled by the LogHandler
6. **No emojis in log messages** - Use appropriate log levels instead

## Log Levels

| Level | Use Case |
|-------|----------|
| `.debug` | Flow tracing, development debugging |
| `.info` | Normal operations, successful actions |
| `.notice` | Important state changes |
| `.warning` | Recoverable issues, unexpected conditions |
| `.error` | Errors requiring attention |
| `.critical` | System failures |

## Examples

```swift
// Good
logger.debug("sendMessage called with \(message.count) chars")
logger.info("Session synced successfully")
logger.warning("Connection retry attempt \(attempt)")
logger.error("Failed to sync: \(error.localizedDescription)")

// Bad - don't do these
print("Debug: something happened")           // No print()
logger.info("Starting sync")                 // No emojis
os_log("Message", log: .default, type: .info) // No direct os.log
```
