# Nextbase

- v4 work is in progress \*
  We are currently working on the v4 of Nextbase in v4-alpha branch. It will contain supabase improvements including the new publishable key appraoch, updated design etc. Work started on 16th September 2025. It is not ready for production use yet. We estimate it will take around 2 weeks to complete.
- Meanwhile please continue using the main branch for your projects.

Nextbase Ultimate is a simple, fast, and secure way to build and deploy your next web application. It's built on top of [Next.js](https://nextjs.org/), [React](https://reactjs.org/), and [Supabase](https://supabase.com/). It is fully typed and uses [TypeScript](https://www.typescriptlang.org/), which means you can build your app with confidence.

## Turborepo workspace

- `apps/web` – Next.js application (was the previous root app)
- `apps/email` – React Email templates and preview tooling
- `apps/database` – Supabase configuration, migrations, and local tooling
- `biome.json` – shared Biome configuration
- `packages/typescript-config` – shared TypeScript compiler options

### Common commands

- `pnpm dev` – run all `dev` processes through Turbo (parallel)
- `pnpm dev:web` – run only the Next.js app
- `pnpm --filter @unbound/web build` – build the web app
- `pnpm --filter @unbound/email dev` – start the React Email preview server
- `pnpm --filter @unbound/database gen:types` – sync Supabase types into the web app

## Developing and deployment instructions

Please checkout the documentation site [here](https://usenextbase.com/docs).

## Relay Server Deployment (Fly.io)

The relay server (`apps/relay`) is deployed to [Fly.io](https://fly.io) and auto-deploys on push to `main`.

### First-time setup

1. **Install Fly CLI:**
   ```bash
   brew install flyctl
   ```

2. **Login to Fly:**
   ```bash
   fly auth login
   ```

3. **Create the app:**
   ```bash
   cd apps/relay && fly launch --no-deploy
   ```

4. **Set secrets:**
   ```bash
   fly secrets set SUPABASE_URL="your-url" SUPABASE_SECRET_KEY="your-key"
   ```

5. **Deploy:**
   ```bash
   fly deploy
   ```

### CI/CD Setup

Auto-deploy is configured via `.github/workflows/deploy-relay.yml`.

1. Generate a deploy token:
   ```bash
   fly tokens create deploy -x 999999h
   ```

2. Add `FLY_API_TOKEN` secret in GitHub repo settings under **Settings > Secrets and variables > Actions**.

Pushes to `main` that modify `apps/relay/**` or `packages/protocol/**` will trigger auto-deploy.

### Useful commands

```bash
fly status          # Check deployment status
fly logs            # View logs
fly ssh console     # SSH into container
fly scale count 2   # Scale instances
```

Thanks!
