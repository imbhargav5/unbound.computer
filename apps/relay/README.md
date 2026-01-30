# Unbound Relay Server

WebSocket relay server for routing encrypted messages between devices. The relay is **crypto-blind** - it routes encrypted payloads without any ability to decrypt them.

## Prerequisites

- Node.js 22+
- pnpm 9+
- Supabase instance with `devices` table

## Environment Variables

Copy `.env.example` to `.env` and configure:

### Required

| Variable | Description |
|----------|-------------|
| `SUPABASE_URL` | Supabase project URL (e.g., `https://your-project.supabase.co`) |
| `SUPABASE_SECRET_KEY` | Supabase service role key (admin access) |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Server port |
| `HOST` | `0.0.0.0` | Listening address |
| `NODE_ENV` | `development` | Environment (`development`, `production`, `test`) |
| `LOG_LEVEL` | `info` | Log level (`debug`, `info`, `warn`, `error`) |
| `HEARTBEAT_INTERVAL_MS` | `30000` | WebSocket heartbeat interval (30s) |
| `CONNECTION_TIMEOUT_MS` | `90000` | Connection idle timeout (90s) |
| `AUTH_TIMEOUT_MS` | `10000` | Authentication timeout (10s) |

## Development

```bash
# Install dependencies
pnpm install

# Run in development mode (watch)
pnpm dev

# Build
pnpm build

# Run production build
pnpm start

# Run tests
pnpm test
```

## API Endpoints

### WebSocket

- **`ws://HOST:PORT/`** - Main WebSocket endpoint for device connections

### HTTP Health Checks

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Liveness check, returns `{"status":"ok"}` |
| `/ready` | GET | Readiness check with connection/session stats |

## Authentication Flow

1. Client connects via WebSocket
2. Client sends `AUTH` message:
   ```json
   {
     "type": "AUTH",
     "deviceToken": "<supabase-jwt>",
     "deviceId": "<uuid>"
   }
   ```
3. Server validates JWT with Supabase
4. Server checks device exists in `devices` table
5. Server sends `AUTH_RESULT` event

## Database Requirements

Requires Supabase `devices` table with columns:

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Device identifier |
| `user_id` | UUID | References auth.users |
| `name` | Text | Device name |
| `device_type` | Text | Device type |
| `is_active` | Boolean | Whether device is active |
| `last_seen_at` | Timestamp | Last connection time |

## Device Roles

| Role | Description |
|------|-------------|
| `executor` | Mac running Claude Code (sends output) |
| `controller` | iOS trust root (sends commands, receives output) |
| `viewer` | Web browser (receives output) |

## Fly.io Deployment

The app is configured for Fly.io deployment:

```bash
# Deploy
fly deploy

# View logs
fly logs

# SSH into instance
fly ssh console
```

### Fly.io Configuration (fly.toml)

| Setting | Value |
|---------|-------|
| App Name | `unbound-computer` |
| Region | `sjc` (San Jose) |
| Internal Port | `8080` |
| Force HTTPS | Yes |
| VM CPU | 1 shared |
| VM Memory | 512 MB |
| Concurrency (soft) | 20 connections |
| Concurrency (hard) | 25 connections |
| Min Machines | 1 |
| Auto-stop | Disabled |

### Health Checks

| Type | Endpoint | Interval | Timeout |
|------|----------|----------|---------|
| HTTP | `/health` | 30s | 5s |
| TCP | Port 8080 | 15s | 2s |

## Docker

```bash
# Build image
docker build -t unbound-relay .

# Run container
docker run -p 8080:8080 \
  -e SUPABASE_URL=https://your-project.supabase.co \
  -e SUPABASE_SECRET_KEY=your-service-role-key \
  unbound-relay
```

## Message Types

The relay routes these message types:

| Type | Direction | Description |
|------|-----------|-------------|
| `AUTH` | Client → Server | Authentication request |
| `AUTH_RESULT` | Server → Client | Authentication result |
| `JOIN_SESSION` | Client → Server | Join a session |
| `LEAVE_SESSION` | Client → Server | Leave a session |
| `STREAM_CHUNK` | Executor → Viewers | Claude output chunk |
| `STREAM_COMPLETE` | Executor → Viewers | Stream finished |
| `REMOTE_CONTROL` | Controller → Executor | Pause/resume/stop/input |
| `CONTROL_ACK` | Executor → Controller | Command acknowledgment |
| `PRESENCE` | Server → Clients | Viewer join/leave events |
| `HEARTBEAT` | Bidirectional | Keep-alive ping |

## Security Notes

- The relay **cannot decrypt** message payloads
- All sensitive content is E2E encrypted between devices
- JWT tokens are validated with Supabase
- Device registration is verified against database
- WebSocket connections require authentication within 10 seconds
