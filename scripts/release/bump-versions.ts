#!/usr/bin/env tsx
/**
 * Bumps version in all package.json and Cargo.toml files
 *
 * Usage:
 *   tsx bump-versions.ts <patch|minor|major>
 *
 * Updates:
 *   - Root package.json
 *   - All apps/*/package.json
 *   - All packages/*/package.json
 *   - apps/daemon/Cargo.toml ([workspace.package].version)
 *   - apps/cli-new/Cargo.toml
 *   - packages/observability/Cargo.toml
 */

import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs"
import { join } from "node:path"

const RELEASE_TYPES = ["patch", "minor", "major"] as const
type ReleaseType = (typeof RELEASE_TYPES)[number]

function bumpVersion(version: string, releaseType: ReleaseType): string {
  const parts = version.split(".").map(Number)

  if (parts.length !== 3 || parts.some(Number.isNaN)) {
    throw new Error(`Invalid version format: ${version}`)
  }

  const [major, minor, patch] = parts

  switch (releaseType) {
    case "major":
      return `${major + 1}.0.0`
    case "minor":
      return `${major}.${minor + 1}.0`
    case "patch":
      return `${major}.${minor}.${patch + 1}`
  }
}

function updatePackageJson(filepath: string, newVersion: string): void {
  const content = readFileSync(filepath, "utf-8")
  const pkg = JSON.parse(content)
  pkg.version = newVersion
  writeFileSync(filepath, `${JSON.stringify(pkg, null, 2)}\n`, "utf-8")
  console.log(`  Updated: ${filepath}`)
}

function updateCargoToml(filepath: string, newVersion: string): void {
  let content = readFileSync(filepath, "utf-8")

  // Handle workspace version: [workspace.package] version = "x.x.x"
  if (content.includes("[workspace.package]")) {
    content = content.replace(
      /(\[workspace\.package\][\s\S]*?version\s*=\s*")[\d.]+(")/,
      `$1${newVersion}$2`
    )
  }

  // Handle package version: [package] version = "x.x.x"
  if (content.includes("[package]")) {
    content = content.replace(
      /(\[package\][\s\S]*?version\s*=\s*")[\d.]+(")/,
      `$1${newVersion}$2`
    )
  }

  writeFileSync(filepath, content, "utf-8")
  console.log(`  Updated: ${filepath}`)
}

function getPackageJsonPaths(rootDir: string): string[] {
  const paths: string[] = []

  // Root package.json
  paths.push(join(rootDir, "package.json"))

  // Apps
  const appsDir = join(rootDir, "apps")
  if (existsSync(appsDir)) {
    for (const app of readdirSync(appsDir)) {
      const pkgPath = join(appsDir, app, "package.json")
      if (existsSync(pkgPath)) {
        paths.push(pkgPath)
      }
    }
  }

  // Packages
  const packagesDir = join(rootDir, "packages")
  if (existsSync(packagesDir)) {
    for (const pkg of readdirSync(packagesDir)) {
      const pkgPath = join(packagesDir, pkg, "package.json")
      if (existsSync(pkgPath)) {
        paths.push(pkgPath)
      }
    }
  }

  return paths
}

function getCargoTomlPaths(rootDir: string): string[] {
  // Only update the main Cargo.toml files, not the individual crates
  // (workspace members inherit from workspace.package)
  return [
    join(rootDir, "apps", "daemon", "Cargo.toml"),
    join(rootDir, "apps", "cli-new", "Cargo.toml"),
    join(rootDir, "packages", "observability", "Cargo.toml"),
  ].filter(existsSync)
}

function main() {
  const releaseType = process.argv[2] as ReleaseType

  if (!releaseType || !RELEASE_TYPES.includes(releaseType)) {
    console.error(`Usage: bump-versions.ts <patch|minor|major>`)
    process.exit(1)
  }

  const rootDir = process.cwd()

  // Get current version from root package.json
  const rootPkgPath = join(rootDir, "package.json")
  const rootPkg = JSON.parse(readFileSync(rootPkgPath, "utf-8"))
  const currentVersion = rootPkg.version

  const newVersion = bumpVersion(currentVersion, releaseType)

  console.log(`Bumping version: ${currentVersion} -> ${newVersion} (${releaseType})`)
  console.log("")

  // Update all package.json files
  console.log("Updating package.json files:")
  const packageJsonPaths = getPackageJsonPaths(rootDir)
  for (const filepath of packageJsonPaths) {
    updatePackageJson(filepath, newVersion)
  }

  console.log("")

  // Update all Cargo.toml files
  console.log("Updating Cargo.toml files:")
  const cargoTomlPaths = getCargoTomlPaths(rootDir)
  for (const filepath of cargoTomlPaths) {
    updateCargoToml(filepath, newVersion)
  }

  console.log("")
  console.log(`Done! All packages bumped to v${newVersion}`)

  // Output the new version for GitHub Actions
  console.log("")
  console.log(`NEW_VERSION=${newVersion}`)
}

main()
