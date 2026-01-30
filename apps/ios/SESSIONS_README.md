# Sessions iOS App

iOS application for viewing coding sessions with real-time updates using Supabase (cold path) and Redis via WebSocket (hot path).

## Architecture

The app follows a **cold + hot** data loading pattern:

1. **Cold Path (Supabase)**: Loads historical session data and events from PostgreSQL
2. **Hot Path (Redis via Relay)**: Subscribes to real-time event streams via WebSocket

### Key Components

```
Sources/
├── Models/
│   ├── CodingSession.swift          # Session data model
│   ├── ConversationEvent.swift      # Event data model with 47+ event types
│   └── WebSocketMessages.swift      # Relay protocol messages
│
├── Services/
│   ├── SupabaseService.swift        # Cold path: Fetch from Supabase
│   ├── RelayWebSocketService.swift  # Hot path: Real-time updates
│   └── AuthenticationService.swift  # Web session QR code auth
│
├── ViewModels/
│   ├── SessionListViewModel.swift   # List screen state management
│   └── SessionDetailViewModel.swift # Detail screen with cold+hot logic
│
├── Views/
│   ├── SessionListView.swift        # List of sessions
│   ├── SessionDetailView.swift      # Session detail with events
│   ├── EventRowView.swift           # Individual event display
│   └── AuthenticationView.swift     # QR code authentication
│
└── Configuration/
    └── Config.swift                 # Environment configuration
```

## Features

### Session List
- ✅ Load all sessions from Supabase
- ✅ Pull-to-refresh
- ✅ Session cards with metadata (device, project, statistics)
- ✅ Status badges (active, paused, completed, etc.)
- ✅ Navigation to detail view

### Session Detail
- ✅ **Cold Load**: Fetch session + last 100 events from Supabase
- ✅ **Hot Subscribe**: WebSocket connection to relay for real-time events
- ✅ **Deduplication**: Prevents duplicate events between cold/hot paths
- ✅ Auto-scroll to latest events
- ✅ Connection status indicator (Live/Disconnected/Reconnecting)
- ✅ Automatic reconnection with exponential backoff
- ✅ Event timeline with categorized icons and colors

### Authentication
- ✅ QR code-based web session flow
- ✅ Keychain credential storage
- ✅ Session restoration on app launch
- ✅ Acts as **viewer** device with configurable permissions

### Event Types Supported

47+ conversation event types including:
- **Output**: `OUTPUT_CHUNK`, `STREAMING_*`
- **Tool**: `TOOL_STARTED`, `TOOL_COMPLETED`, `TOOL_FAILED`
- **Questions**: `QUESTION_ASKED`, `QUESTION_ANSWERED`
- **Files**: `FILE_CREATED`, `FILE_MODIFIED`, `FILE_DELETED`
- **Execution**: `EXECUTION_STARTED`, `EXECUTION_COMPLETED`
- **Session State**: `SESSION_STATE_CHANGED`, `SESSION_ERROR`
- **TODOs**: `TODO_LIST_UPDATED`, `TODO_ITEM_UPDATED`

## Setup

### Prerequisites

- Xcode 15.0+
- iOS 17.0+
- Swift 5.9+

### Installation

1. **Install dependencies**:
   ```bash
   cd apps/ios
   swift package resolve
   ```

2. **Configure environment variables**:

   Set environment variables in Xcode scheme or use `.xcconfig`:

   ```bash
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-anon-key
   RELAY_WS_URL=wss://relay.unbound.computer
   API_URL=https://api.unbound.computer
   ```

3. **Open in Xcode**:
   ```bash
   open unbound-ios.xcodeproj
   ```

4. **Add SessionsApp as a target** (if not already):
   - File > New > Target
   - Choose "App"
   - Name: "SessionsApp"
   - Link the `Sources/` directory

5. **Run the app**:
   - Select SessionsApp scheme
   - Select a simulator or device
   - Press `Cmd+R` to build and run

## Usage

### First Launch

1. App opens to authentication screen
2. Tap "Generate QR Code"
3. Scan QR code with your trusted device (macOS executor)
4. Wait for authorization
5. App loads sessions automatically

### Viewing Sessions

1. Sessions list displays all coding sessions
2. Tap any session to view details
3. Detail view loads historical events (cold path)
4. WebSocket connects for real-time updates (hot path)
5. New events appear automatically as they stream in

### Connection States

- 🟢 **Live**: Connected and receiving real-time events
- 🟠 **Connecting**: Establishing WebSocket connection
- 🟠 **Reconnecting (N)**: Attempting to reconnect after failure
- 🔴 **Disconnected**: Not connected to relay
- 🔴 **Failed**: Connection failed

## Architecture Details

### Cold + Hot Pattern

```
┌─────────────────────────────────────────┐
│         Session Detail View             │
│                                         │
│  1. Cold Load (Immediate)               │
│     ↓                                   │
│     Supabase.fetchSession()             │
│     Supabase.fetchEvents(limit: 100)    │
│                                         │
│  2. Hot Subscribe (Real-time)           │
│     ↓                                   │
│     WebSocket.connect()                 │
│     WebSocket.authenticate()            │
│     WebSocket.subscribe(sessionId)      │
│     ↓                                   │
│     for await event in stream {         │
│       if !seen(event.id) {              │
│         append(event)                   │
│       }                                 │
│     }                                   │
└─────────────────────────────────────────┘
```

### Deduplication Strategy

```swift
// Track events loaded from cold path
private var seenEventIds = Set<String>()

// Cold load
let events = try await supabase.fetchEvents(...)
seenEventIds = Set(events.map { $0.eventId })

// Hot stream
for await event in websocket.eventStream {
    guard !seenEventIds.contains(event.eventId) else {
        continue // Skip duplicate
    }

    events.append(event)
    seenEventIds.insert(event.eventId)
}
```

### Reconnection Logic

```swift
// Exponential backoff with max 30 seconds
let delay = min(pow(2.0, Double(attempts)), 30.0)
try await Task.sleep(for: .seconds(delay))

// Retry up to 10 times
if attempts < maxReconnectAttempts {
    try await connect()
}
```

## Data Flow

```
macOS Executor
    ↓ HTTP POST /events
[Relay Server]
    ↓ XADD to Redis Stream
[Redis: session:X:cvs]
    ↓
┌───┴────┐
↓        ↓
[Relay]  [Persist Worker]
WebSocket   ↓
    ↓    Supabase DB
    ↓       ↑
iOS App ────┘
 (Hot)   (Cold)
```

## Performance

- **Cold Load**: ~200-500ms for 100 events
- **Hot Latency**: ~50-100ms from event creation to display
- **Memory**: Efficient with lazy loading and pagination
- **Battery**: WebSocket connection optimized for low power usage

## Security

- ✅ Credentials stored securely in Keychain
- ✅ HTTPS/WSS only (no insecure connections)
- ✅ Row-Level Security (RLS) on Supabase enforced by user_id
- ✅ QR code-based device authorization
- ✅ Session tokens with 24-hour expiration

## Troubleshooting

### WebSocket Connection Issues

If the app shows "Disconnected" or "Failed":

1. Check relay server URL in Config.swift
2. Verify network connectivity
3. Check logs for authentication errors
4. Ensure device token is valid

### Events Not Appearing

1. Verify cold load completed successfully
2. Check WebSocket connection state (should be "Live")
3. Verify session ID matches between cold and hot paths
4. Check relay server logs for subscription status

### QR Code Not Working

1. Ensure API URL is correct
2. Check web session API endpoints are accessible
3. Verify trusted device has permission to authorize
4. Check session hasn't expired (5-minute timeout)

## Development

### File Structure

All source files are in `Sources/` and organized by layer:

- **Models**: Data structures (Codable, Sendable)
- **Services**: Business logic and networking (actors for concurrency safety)
- **ViewModels**: State management (@MainActor, ObservableObject)
- **Views**: SwiftUI views

### Code Style

Following **Ultracite** standards from project root:

- Explicit types for clarity
- `async/await` over completion handlers
- SwiftUI function components
- Proper error handling
- No magic numbers (use named constants)

### Testing

```bash
# Run unit tests
swift test

# Run with coverage
swift test --enable-code-coverage
```

## Integration with Existing App

This Sessions viewer can be integrated into the existing `unbound-ios` app:

1. **Option 1: Separate Tab**
   - Add SessionListView as a tab in TabView
   - Share AuthenticationService with main app

2. **Option 2: Deep Link**
   - Add URL scheme for `unbound://sessions/:id`
   - Navigate from main app to session detail

3. **Option 3: Embedded View**
   - Use SessionDetailView as a child view
   - Pass sessionId from parent context

## See Also

- [Architecture Plan](../../docs/ios-sessions-architecture-plan.md) - Full architectural documentation
- [Main iOS README](README.md) - Main Unbound iOS app documentation
- [Relay Documentation](../relay/README.md) - WebSocket relay server docs
