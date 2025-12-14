// The below can be used in a Jest global setup file or similar for your testing set-up
import { execSync } from "child_process";
import { config as dotenvConfig } from "dotenv";
import fs from "fs";
import path from "path";

interface SupabaseStatus {
  PUBLISHABLE_KEY: string;
  SECRET_KEY: string;
  DB_URL: string;
}

function parseEnvOutput(output: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const line of output.split("\n")) {
    const match = line.match(/^([A-Z_]+)="(.+)"$/);
    if (match) result[match[1]] = match[2];
  }
  return result;
}

export default async () => {
  const projectDir = process.cwd();
  const envTestPath = path.join(projectDir, ".env.test");
  const envTestLocalPath = path.join(projectDir, ".env.test.local");

  console.log("[global-setup] Project dir:", projectDir);

  // Copy .env.test to .env.test.local as base
  if (fs.existsSync(envTestPath)) {
    fs.copyFileSync(envTestPath, envTestLocalPath);
    console.log("[global-setup] Copied .env.test to .env.test.local");
  } else {
    throw new Error(`[global-setup] .env.test not found at ${envTestPath}`);
  }

  // Get supabase status from apps/database as JSON
  const databaseDir = path.join(projectDir, "..", "..", "apps", "database");
  console.log("[global-setup] Running supabase status in:", databaseDir);

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
    console.log("[global-setup] Supabase status parsed successfully");
  } catch (error) {
    const err = error as { stderr?: string; stdout?: string };
    console.error("[global-setup] Failed to run supabase status");
    console.error("[global-setup] stdout:", err.stdout);
    console.error("[global-setup] stderr:", err.stderr);
    throw new Error(
      "[global-setup] Supabase is not running. Start it with: cd apps/database && pnpm supabase start"
    );
  }

  // Extract keys and DB URL from env output
  const publishableKey = statusParsed.PUBLISHABLE_KEY;
  const secretKey = statusParsed.SECRET_KEY;
  const dbUrl = statusParsed.DB_URL;

  console.log(
    "[global-setup] PUBLISHABLE_KEY found:",
    publishableKey ? "yes" : "no"
  );
  console.log("[global-setup] SECRET_KEY found:", secretKey ? "yes" : "no");
  console.log("[global-setup] DB_URL found:", dbUrl ? "yes" : "no");

  if (!(publishableKey && secretKey && dbUrl)) {
    throw new Error(
      "[global-setup] Failed to extract Supabase keys/URL from status output"
    );
  }

  let envContent = fs.readFileSync(envTestLocalPath, "utf-8");
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
  fs.writeFileSync(envTestLocalPath, envContent);
  console.log(
    "[global-setup] Updated .env.test.local with Supabase keys and DB URL"
  );

  // Load the environment variables into process.env
  dotenvConfig({ path: envTestLocalPath });
  console.log("[global-setup] Environment loaded successfully");
};
