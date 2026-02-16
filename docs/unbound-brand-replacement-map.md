# Unbound Brand Replacement Map

This document is the source of truth for replacing all legacy Nextbase branding.

## Canonical Names

- Product name: `Unbound`
- Company/organization display name: `Unbound`
- Docs suffix in titles: `Unbound docs`

## Domain and URL Policy

- Primary app/site domain: `unbound.computer`
- Default metadata base URL: `https://unbound.computer`
- Auth/JWT issuer URL: `https://unbound.computer`
- Documentation API URL base: `https://docs.unbound.computer/api`
- Legacy domains to replace:
- `ultimate-demo.usenextbase.com`
- `usenextbase.com`
- `docs.nextbase.dev`

## Email Policy

- Replace legacy test/admin emails from `@usenextbase.com` to `@unbound.computer`
- Standard test admin email: `testadmin@unbound.computer`

## Asset Naming Policy

- Replace logo asset filename references from `nextbase-logo.png` to `unbound-logo.png`
- Keep existing storage bucket/path conventions unless explicitly migrated later

## Slug Policy

- Replace URL/content slugs containing `nextbase` with `unbound`
- Example: `getting-started-with-nextbase` -> `getting-started-with-unbound`
- When slug changes, update all relationship references in seed/test data in the same change

## Internal Tooling Naming Policy

- Keep `.nextbase-references` unchanged (internal tooling path)
- Rename CSS class `.nextbase-editor` to `.unbound-editor`

## Linear URL Policy

- Keep current Linear team slug (`nextbase`) unchanged for now
- Do not modify integration endpoint paths that depend on workspace slug
