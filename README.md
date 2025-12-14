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
- `pnpm --filter @nextbase/web build` – build the web app
- `pnpm --filter @nextbase/email dev` – start the React Email preview server
- `pnpm --filter @nextbase/database gen:types` – sync Supabase types into the web app

## Developing and deployment instructions

Please checkout the documentation site [here](https://usenextbase.com/docs).

Thanks!
