#!/usr/bin/env tsx
/**
 * Removes all release marker files from .releases/ (except README.md and .gitkeep)
 *
 * Usage:
 *   tsx cleanup-releases.ts
 */

import { readdirSync, unlinkSync } from "node:fs";
import { join } from "node:path";

function main() {
  const releasesDir = join(process.cwd(), ".releases");

  let files: string[];
  try {
    files = readdirSync(releasesDir);
  } catch {
    console.log("No .releases directory found");
    return;
  }

  const filesToDelete = files.filter(
    (f) => f.endsWith(".md") && f !== "README.md"
  );

  if (filesToDelete.length === 0) {
    console.log("No release files to clean up");
    return;
  }

  console.log("Cleaning up release files:");
  for (const file of filesToDelete) {
    const filepath = join(releasesDir, file);
    unlinkSync(filepath);
    console.log(`  Deleted: ${file}`);
  }

  console.log(`Done! Removed ${filesToDelete.length} release file(s)`);
}

main();
