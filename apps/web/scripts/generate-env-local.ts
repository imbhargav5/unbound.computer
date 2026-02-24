// Script to generate .env.local with Supabase keys from local Supabase instance
import { execSync } from "child_process";
import fs from "fs";
import path from "path";

interface SupabaseStatus {
  DB_URL: string;
  PUBLISHABLE_KEY: string;
  SECRET_KEY: string;
}

function parseEnvOutput(output: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const line of output.split("\n")) {
    const match = line.match(/^([A-Z_]+)="(.+)"$/);
    if (match) result[match[1]] = match[2];
  }
  return result;
}

function main() {
  const projectDir = path.resolve(import.meta.dirname, "..");
  const envExamplePath = path.join(projectDir, ".env.local.example");
  const envLocalPath = path.join(projectDir, ".env.local");

  console.log("[generate-env-local] Project dir:", projectDir);

  // Copy .env.local.example to .env.local as base
  if (fs.existsSync(envExamplePath)) {
    fs.copyFileSync(envExamplePath, envLocalPath);
    console.log("[generate-env-local] Copied .env.local.example to .env.local");
  } else {
    throw new Error(
      `[generate-env-local] .env.local.example not found at ${envExamplePath}`
    );
  }

  // Get supabase status from apps/database
  const databaseDir = path.join(projectDir, "..", "database");
  console.log("[generate-env-local] Running supabase status in:", databaseDir);

  let statusParsed: SupabaseStatus;
  try {
    const statusOutput = execSync("pnpm supabase status --output env", {
      cwd: databaseDir,
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    });
    const parsed = parseEnvOutput(statusOutput);
    statusParsed = {
      PUBLISHABLE_KEY: parsed.PUBLISHABLE_KEY,
      SECRET_KEY: parsed.SECRET_KEY,
      DB_URL: parsed.DB_URL,
    };
    console.log("[generate-env-local] Supabase status parsed successfully");
  } catch (error) {
    const err = error as { stderr?: string; stdout?: string };
    console.error("[generate-env-local] Failed to run supabase status");
    console.error("[generate-env-local] stdout:", err.stdout);
    console.error("[generate-env-local] stderr:", err.stderr);
    throw new Error(
      "[generate-env-local] Supabase is not running. Start it with: cd apps/database && pnpm supabase start"
    );
  }

  // Extract keys and DB URL from env output
  const publishableKey = statusParsed.PUBLISHABLE_KEY;
  const secretKey = statusParsed.SECRET_KEY;
  const dbUrl = statusParsed.DB_URL;

  console.log(
    "[generate-env-local] PUBLISHABLE_KEY found:",
    publishableKey ? "yes" : "no"
  );
  console.log(
    "[generate-env-local] SECRET_KEY found:",
    secretKey ? "yes" : "no"
  );
  console.log("[generate-env-local] DB_URL found:", dbUrl ? "yes" : "no");

  if (!(publishableKey && secretKey && dbUrl)) {
    throw new Error(
      "[generate-env-local] Failed to extract Supabase keys/URL from status output"
    );
  }

  let envContent = fs.readFileSync(envLocalPath, "utf-8");
  envContent = envContent.replace(
    /NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=.*/,
    `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=${publishableKey}`
  );
  envContent = envContent.replace(
    /SUPABASE_SECRET_KEY=.*/,
    `SUPABASE_SECRET_KEY=${secretKey}`
  );
  envContent = envContent.replace(
    /SUPABASE_POSTGRES_DB_URL=.*/,
    `SUPABASE_POSTGRES_DB_URL=${dbUrl}`
  );
  fs.writeFileSync(envLocalPath, envContent);
  console.log(
    "[generate-env-local] Updated .env.local with Supabase keys and DB URL"
  );
}

main();
