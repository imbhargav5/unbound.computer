# Session Rename Cross-Device Checklist

## Preconditions
- Signed in on macOS and iOS with same user.
- Supabase realtime available for `agent_coding_sessions`.

## Steps
1. On macOS, right-click a session in the sidebar and choose `Rename...`.
2. Enter a new title (non-empty) and click `Save`.
3. Verify the sidebar row updates immediately on macOS.
4. Verify the Supabase row `agent_coding_sessions.title` updates for that session.
5. On iOS, confirm the session list and detail view reflect the new title without relaunch.

## Stale Update Guard
1. Rename the same session twice quickly on macOS.
2. Confirm iOS reflects the latest title only (no revert to older title).
