# Unbound Desktop

Tauri desktop client for Unbound. This app is the primary macOS desktop surface and talks to `unbound-daemon` over the existing local IPC socket.

## Runtime model

- Production desktop builds do not bundle the daemon.
- `unbound-daemon` is packaged and installed separately.
- The desktop app checks daemon health and version compatibility on startup.
- If the daemon is missing, stale, or incompatible, the desktop app blocks on an install/update screen.

## Development

From the repository root:

```bash
# Run the Tauri desktop shell directly
pnpm desktop:dev

# Or run the daemon and desktop app together
pnpm daemon:dev:app
```

From `apps/desktop`:

```bash
pnpm tauri:dev
```

## Build

```bash
pnpm --filter @unbound/desktop build
pnpm --filter @unbound/desktop tauri:build
```

## Production packaging

The canonical macOS release path is the repo-level release script:

```bash
./scripts/release/build-macos-release.sh
```

That script produces separate desktop-app and daemon artifacts under `dist/macos/`.
