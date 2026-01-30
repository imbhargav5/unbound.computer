# iOS Sessions App - Quick Start Guide

## 🚀 Get Started in 5 Minutes

### Step 1: Install Dependencies

```bash
cd apps/ios
swift package resolve
```

This will download the Supabase Swift SDK (~2.5.0).

### Step 2: Configure Environment

Create or edit `Config/Debug.xcconfig`:

```bash
cp Config/Debug.xcconfig.template Config/Debug.xcconfig
```

Add your configuration:

```ini
SUPABASE_URL = https://your-project.supabase.co
SUPABASE_ANON_KEY = your-supabase-anon-key
RELAY_WS_URL = wss://relay.unbound.computer
API_URL = https://api.unbound.computer
```

Or set environment variables directly in Xcode:
1. **Product** > **Scheme** > **Edit Scheme**
2. **Run** > **Arguments** tab
3. Add environment variables

### Step 3: Verify Database Schema

Ensure these tables exist in your Supabase project:

**sessions table:**
```sql
CREATE TABLE sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  title TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_activity_at TIMESTAMPTZ,
  executor_device_id UUID,
  executor_device_name TEXT,
  project_path TEXT,
  event_count INTEGER DEFAULT 0,
  tool_call_count INTEGER DEFAULT 0,
  error_count INTEGER DEFAULT 0
);

-- Enable RLS
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;

-- Users can only see their own sessions
CREATE POLICY "Users can view own sessions"
  ON sessions FOR SELECT
  USING (auth.uid() = user_id);
```

**conversation_events table:**
```sql
CREATE TABLE conversation_events (
  event_id TEXT PRIMARY KEY,
  session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  payload JSONB,
  stream_id TEXT
);

-- Index for fast session queries
CREATE INDEX idx_conversation_events_session_id
  ON conversation_events(session_id);

CREATE INDEX idx_conversation_events_created_at
  ON conversation_events(created_at);

-- Enable RLS
ALTER TABLE conversation_events ENABLE ROW LEVEL SECURITY;

-- Users can only see events for their own sessions
CREATE POLICY "Users can view own session events"
  ON conversation_events FOR SELECT
  USING (
    session_id IN (
      SELECT id FROM sessions WHERE user_id = auth.uid()
    )
  );
```

### Step 4: Build and Run

#### Option A: Standalone App (Recommended for testing)

```bash
# Open in Xcode
open Package.swift

# Or create new Xcode project
# File > New > Project > App
# Add Sources/ as source group
# Link SessionsApp package
```

Then in Xcode:
1. Select SessionsApp scheme
2. Choose simulator (iPhone 15 Pro recommended)
3. Press `Cmd+R` to build and run

#### Option B: Integrate with Existing App

If you have the existing `unbound-ios` app:

```swift
// In your main app's ContentView or TabView
import SwiftUI

struct MainAppView: View {
    var body: some View {
        TabView {
            // Existing tabs...

            SessionListView()
                .environmentObject(AuthenticationService.shared)
                .tabItem {
                    Label("Sessions", systemImage: "list.bullet")
                }
        }
    }
}
```

### Step 5: Test the App

1. **Launch App**
   - Opens to authentication screen

2. **Generate QR Code**
   - Tap "Generate QR Code"
   - QR code appears

3. **Authorize** (requires backend setup)
   - Scan QR with trusted device
   - Or skip for development (mock data)

4. **View Sessions**
   - List of sessions loads from Supabase
   - Pull to refresh

5. **View Session Detail**
   - Tap any session
   - Events load (cold path)
   - WebSocket connects (hot path)
   - See "Live" indicator when connected

## 📱 Testing Without Full Backend

For development, you can mock the services:

### Mock SupabaseService

```swift
class MockSupabaseService: SupabaseService {
    override func fetchSessions() async throws -> [CodingSession] {
        return [
            CodingSession(
                id: UUID(),
                userId: UUID(),
                title: "Test Session 1",
                status: .active,
                createdAt: Date(),
                updatedAt: Date(),
                lastActivityAt: Date(),
                executorDeviceId: UUID(),
                executorDeviceName: "MacBook Pro",
                projectPath: "/Users/test/project",
                eventCount: 42,
                toolCallCount: 12,
                errorCount: 0
            )
        ]
    }

    override func fetchEvents(
        sessionId: UUID,
        limit: Int,
        offset: Int,
        orderBy: OrderBy
    ) async throws -> [ConversationEvent] {
        return [
            ConversationEvent(
                eventId: "event-1",
                sessionId: sessionId,
                type: .outputChunk,
                createdAt: Date(),
                payload: .text("Hello from Claude!")
            ),
            ConversationEvent(
                eventId: "event-2",
                sessionId: sessionId,
                type: .toolStarted,
                createdAt: Date(),
                payload: .json(["toolName": AnyCodable("bash")])
            )
        ]
    }
}

// Use in SessionListViewModel
init(supabaseService: SupabaseService = MockSupabaseService()) {
    self.supabaseService = supabaseService
}
```

### Skip Authentication

```swift
// In AuthenticationService
init() {
    // Auto-authenticate for development
    #if DEBUG
    isAuthenticated = true
    deviceToken = "mock-token"
    deviceId = "mock-device-id"
    #else
    restoreSession()
    #endif
}
```

## 🐛 Troubleshooting

### Issue: "No such module 'Supabase'"

**Solution:**
```bash
swift package resolve
swift package update
```

Then restart Xcode.

### Issue: "Connection failed"

**Solution:**
1. Check `RELAY_WS_URL` is correct
2. Verify relay server is running
3. Check network connection
4. Look for firewall issues

### Issue: "Authentication failed"

**Solution:**
1. Verify `API_URL` is correct
2. Check web session endpoints are accessible
3. Use mock auth for development (see above)

### Issue: "No sessions appearing"

**Solution:**
1. Check Supabase connection
2. Verify `SUPABASE_URL` and `SUPABASE_ANON_KEY`
3. Check RLS policies allow your user to read sessions
4. Add test data to database

### Issue: Build errors

**Solution:**
1. Clean build folder: `Product > Clean Build Folder` (Shift+Cmd+K)
2. Delete derived data: `~/Library/Developer/Xcode/DerivedData`
3. Restart Xcode
4. Resolve packages again

## 📊 Add Test Data

Run this SQL in Supabase SQL Editor:

```sql
-- Create test user (replace with your actual user ID)
DO $$
DECLARE
  test_user_id UUID := auth.uid(); -- Or hardcode your user ID
  test_session_id UUID := gen_random_uuid();
BEGIN
  -- Insert test session
  INSERT INTO sessions (
    id, user_id, title, status,
    executor_device_name, project_path,
    event_count, tool_call_count, error_count
  ) VALUES (
    test_session_id,
    test_user_id,
    'Test Coding Session',
    'active',
    'MacBook Pro',
    '/Users/test/my-project',
    5, 2, 0
  );

  -- Insert test events
  INSERT INTO conversation_events (event_id, session_id, type, payload) VALUES
    ('evt-1', test_session_id, 'OUTPUT_CHUNK', '{"text": "Starting Claude Code session..."}'::jsonb),
    ('evt-2', test_session_id, 'TOOL_STARTED', '{"toolName": "bash", "command": "ls -la"}'::jsonb),
    ('evt-3', test_session_id, 'TOOL_OUTPUT_CHUNK', '{"text": "total 42\ndrwxr-xr-x  5 user  staff  160 Jan 20 10:00 ."}'::jsonb),
    ('evt-4', test_session_id, 'TOOL_COMPLETED', '{"toolName": "bash", "exitCode": 0}'::jsonb),
    ('evt-5', test_session_id, 'OUTPUT_CHUNK', '{"text": "Directory listing complete!"}'::jsonb);
END $$;
```

## 🎯 Expected Behavior

### Session List
- Shows test session with title "Test Coding Session"
- Status badge shows "Active" in green
- Card displays "MacBook Pro" as device
- Statistics show 5 events, 2 tool calls

### Session Detail
- Header shows session title and metadata
- Timeline displays 5 events in chronological order
- Each event has appropriate icon and color
- Connection indicator shows current state

### Real-time Updates
- When relay is connected, indicator shows "Live" in green
- New events appear automatically as they stream in
- Auto-scrolls to bottom when new events arrive

## 📚 Next Steps

1. **Read the Architecture Plan**: See `docs/ios-sessions-architecture-plan.md`
2. **Review Implementation**: See `IMPLEMENTATION_STATUS.md`
3. **Explore the Code**: Start with `SessionListView.swift`
4. **Test Real-time**: Connect to live relay server
5. **Customize UI**: Modify event rendering in `EventRowView.swift`

## 🆘 Need Help?

- Check `SESSIONS_README.md` for detailed documentation
- Review code comments in source files
- Check Xcode console for `Config.log()` messages
- Look for errors in Supabase dashboard

## ✅ Checklist

Before running the app, ensure:

- [ ] Swift package resolved successfully
- [ ] Environment variables configured
- [ ] Database schema created
- [ ] RLS policies enabled
- [ ] Test data inserted (optional)
- [ ] Xcode project opened
- [ ] Scheme selected
- [ ] Simulator/device chosen

Then press `Cmd+R` and enjoy! 🎉
