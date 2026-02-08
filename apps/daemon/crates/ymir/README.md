# ymir

Authentication and session management for the daemon.

## Purpose

Handles OAuth login flow, token refresh, and session state. Integrates with Supabase for device registration and session secret management.

## Key Features

- **OAuth flow**: Local HTTP callback server for browser auth
- **Token refresh**: Automatic background token renewal
- **FSM-based state**: Explicit auth state machine (logged out → authenticating → authenticated)
- **Supabase client**: Device and session secret API calls
