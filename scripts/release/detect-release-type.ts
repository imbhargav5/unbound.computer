#!/usr/bin/env tsx
/**
 * Detects the release type by reading all .releases/*.md files
 * Returns the highest priority type: major > minor > patch
 *
 * Usage:
 *   tsx detect-release-type.ts
 *
 * Output (stdout):
 *   major | minor | patch | none
 */

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const RELEASE_TYPES = ["major", "minor", "patch"] as const;
type ReleaseType = (typeof RELEASE_TYPES)[number];

function extractReleaseType(content: string): ReleaseType | null {
  // Check frontmatter first
  const frontmatterMatch = content.match(/^---\s*\n([\s\S]*?)\n---/);
  if (frontmatterMatch) {
    const frontmatter = frontmatterMatch[1];
    const typeMatch = frontmatter.match(/type:\s*(major|minor|patch)/);
    if (typeMatch) {
      return typeMatch[1] as ReleaseType;
    }
  }

  // Fallback: check content for keywords
  const lowerContent = content.toLowerCase();
  if (lowerContent.includes("major")) {
    return "major";
  }
  if (lowerContent.includes("minor")) {
    return "minor";
  }
  if (lowerContent.includes("patch")) {
    return "patch";
  }

  return null;
}

function main() {
  const releasesDir = join(process.cwd(), ".releases");

  let files: string[];
  try {
    files = readdirSync(releasesDir).filter(
      (f) => f.endsWith(".md") && f !== "README.md"
    );
  } catch {
    console.log("none");
    return;
  }

  if (files.length === 0) {
    console.log("none");
    return;
  }

  const types: ReleaseType[] = [];

  for (const file of files) {
    const filepath = join(releasesDir, file);
    const content = readFileSync(filepath, "utf-8");
    const releaseType = extractReleaseType(content);
    if (releaseType) {
      types.push(releaseType);
    }
  }

  if (types.length === 0) {
    console.log("none");
    return;
  }

  // Return highest priority
  if (types.includes("major")) {
    console.log("major");
  } else if (types.includes("minor")) {
    console.log("minor");
  } else {
    console.log("patch");
  }
}

main();
