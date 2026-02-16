# Outbound Brand Replacement Map

This document is the source of truth for replacing all legacy Nextbase branding.

## Canonical Names

- Product name: `Outbound`
- Company/organization display name: `Outbound`
- Docs suffix in titles: `Outbound docs`

## Domain and URL Policy

- Primary app/site domain: `outbound.new`
- Default metadata base URL: `https://outbound.new`
- Auth/JWT issuer URL: `https://outbound.new`
- Documentation API URL base: `https://docs.outbound.new/api`
- Legacy domains to replace:
- `ultimate-demo.usenextbase.com`
- `usenextbase.com`
- `docs.nextbase.dev`

## Email Policy

- Replace legacy test/admin emails from `@usenextbase.com` to `@outbound.new`
- Standard test admin email: `testadmin@outbound.new`

## Asset Naming Policy

- Replace logo asset filename references from `nextbase-logo.png` to `outbound-logo.png`
- Keep existing storage bucket/path conventions unless explicitly migrated later

## Slug Policy

- Replace URL/content slugs containing `nextbase` with `outbound`
- Example: `getting-started-with-nextbase` -> `getting-started-with-outbound`
- When slug changes, update all relationship references in seed/test data in the same change

## Internal Tooling Naming Policy

- Rename `.nextbase-references` to `.outbound-references`
- Rename CSS class `.nextbase-editor` to `.outbound-editor`

## Linear URL Policy

- Keep current Linear team slug (`nextbase`) unchanged for now
- Do not modify integration endpoint paths that depend on workspace slug
