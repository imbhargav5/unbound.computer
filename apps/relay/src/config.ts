import { z } from "zod";

const ConfigSchema = z.object({
  // Server
  PORT: z.coerce.number().default(8080),
  HOST: z.string().default("0.0.0.0"),
  NODE_ENV: z
    .enum(["development", "production", "test"])
    .default("development"),
  LOG_LEVEL: z.enum(["debug", "info", "warn", "error"]).default("info"),

  // Supabase
  SUPABASE_URL: z.string().url(),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(1),

  // Timeouts (milliseconds)
  HEARTBEAT_INTERVAL_MS: z.coerce.number().default(30_000), // 30 seconds
  CONNECTION_TIMEOUT_MS: z.coerce.number().default(90_000), // 90 seconds
  AUTH_TIMEOUT_MS: z.coerce.number().default(10_000), // 10 seconds
});

export type Config = z.infer<typeof ConfigSchema>;

function loadConfig(): Config {
  const result = ConfigSchema.safeParse(process.env);

  if (!result.success) {
    console.error("Invalid configuration:");
    for (const issue of result.error.issues) {
      console.error(`  ${issue.path.join(".")}: ${issue.message}`);
    }
    process.exit(1);
  }

  return result.data;
}

export const config = loadConfig();
