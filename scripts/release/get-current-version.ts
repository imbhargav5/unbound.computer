#!/usr/bin/env tsx
/**
 * Gets the current version from the root package.json
 *
 * Usage:
 *   tsx get-current-version.ts
 *
 * Output (stdout):
 *   0.0.2
 */

import { readFileSync } from "node:fs";
import { join } from "node:path";

function main() {
  const packageJsonPath = join(process.cwd(), "package.json");
  const packageJson = JSON.parse(readFileSync(packageJsonPath, "utf-8"));
  console.log(packageJson.version);
}

main();
