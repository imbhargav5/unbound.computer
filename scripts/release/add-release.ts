#!/usr/bin/env tsx
/**
 * Creates a release marker file in .releases/
 *
 * Usage:
 *   pnpm release:patch
 *   pnpm release:minor
 *   pnpm release:major
 */

import { writeFileSync } from "node:fs"
import { join } from "node:path"

const RELEASE_TYPES = ["patch", "minor", "major"] as const
type ReleaseType = (typeof RELEASE_TYPES)[number]

function main() {
  const releaseType = process.argv[2] as ReleaseType

  if (!releaseType || !RELEASE_TYPES.includes(releaseType)) {
    console.error(`Usage: add-release.ts <patch|minor|major>`)
    console.error(`  patch - Bug fixes (0.0.1 -> 0.0.2)`)
    console.error(`  minor - New features (0.0.1 -> 0.1.0)`)
    console.error(`  major - Breaking changes (0.0.1 -> 1.0.0)`)
    process.exit(1)
  }

  const timestamp = Date.now()
  const filename = `release-${timestamp}.md`
  const releasesDir = join(process.cwd(), ".releases")
  const filepath = join(releasesDir, filename)

  const content = `---
type: ${releaseType}
---
`

  writeFileSync(filepath, content, "utf-8")

  console.log(`Created ${releaseType} release marker: .releases/${filename}`)
  console.log(``)
  console.log(`Next steps:`)
  console.log(`  1. git add .releases/`)
  console.log(`  2. git commit -m "chore: prepare ${releaseType} release"`)
  console.log(`  3. git push`)
  console.log(``)
  console.log(`GitHub Actions will create a release PR automatically.`)
}

main()
