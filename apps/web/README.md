# Unbound Web App

Next.js 16 web application for the Unbound platform.

## Prerequisites

- Node.js 20+
- pnpm 9+
- Supabase CLI (for local development)

## Environment Variables

Copy `.env.example` to `.env.local` and configure the following:

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `NEXT_PUBLIC_SUPABASE_URL` | Public | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Public | Supabase anonymous/publishable key |
| `SUPABASE_SECRET_KEY` | Secret | Supabase service role key |
| `SUPABASE_JWT_SIGNING_KEY` | Secret | JWT signing key for token validation |
| `STRIPE_SECRET_KEY` | Secret | Stripe secret API key |
| `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | Public | Stripe publishable key |
| `STRIPE_WEBHOOK_SECRET` | Secret | Stripe webhook signing secret |
| `ADMIN_EMAIL` | Secret | Admin email for notifications |
| `RESEND_API_KEY` | Secret | Resend email service API key |
| `UNKEY_ROOT_KEY` | Secret | Unkey root API key |
| `UNKEY_API_ID` | Secret | Unkey API identifier |

### Analytics & Monitoring

| Variable | Type | Description |
|----------|------|-------------|
| `NEXT_PUBLIC_POSTHOG_API_KEY` | Public | PostHog analytics API key |
| `NEXT_PUBLIC_POSTHOG_APP_ID` | Public | PostHog app ID |
| `NEXT_PUBLIC_POSTHOG_HOST` | Public | PostHog server URL |
| `NEXT_PUBLIC_GA_ID` | Public | Google Analytics ID |
| `NEXT_PUBLIC_SENTRY_DSN` | Public | Sentry error tracking DSN |

### Site Configuration

| Variable | Type | Description | Default |
|----------|------|-------------|---------|
| `NEXT_PUBLIC_SITE_URL` | Public | Application public URL | `http://localhost:3000` |
| `NEXT_PUBLIC_RELAY_URL` | Public | Relay WebSocket URL | `ws://localhost:8080` |

### OAuth Providers (Optional)

| Variable | Type | Description |
|----------|------|-------------|
| `GITHUB_CLIENT_ID` | Secret | GitHub OAuth client ID |
| `GITHUB_CLIENT_SECRET` | Secret | GitHub OAuth client secret |
| `GOOGLE_CLIENT_ID` | Secret | Google OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | Secret | Google OAuth client secret |
| `TWITTER_API_KEY` | Secret | Twitter/X API key |
| `TWITTER_API_SECRET` | Secret | Twitter/X API secret |

### Development Options

| Variable | Type | Description |
|----------|------|-------------|
| `USE_LOCAL_EMAIL` | String | Set to `"true"` to skip sending real emails |
| `NODE_ENV` | String | `development`, `test`, or `production` |

## Development

```bash
# Install dependencies
pnpm install

# Start local Supabase
pnpm supabase start

# Run development server
pnpm dev

# Build for production
pnpm build

# Run production build
pnpm start
```

## Local Supabase

For local development, the app expects Supabase at `http://127.0.0.1:54321`.

Default local credentials:
- URL: `http://127.0.0.1:54321`
- Anon Key: (see Supabase CLI output)
- Database: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`

## Code Quality

```bash
# Format and lint
npx ultracite fix

# Check for issues
npx ultracite check
```
