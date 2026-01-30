import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import * as z from "zod";

import { AckFrame } from "../src/schemas/ack";
import { AnyEvent } from "../src/schemas/any-event";
import { HandshakeEvent } from "../src/schemas/handshake-events";
import { SessionEvent } from "../src/schemas/session-events";

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUTPUT_DIR = join(__dirname, "../generated/json-schemas");

const schemas = {
  AckFrame,
  HandshakeEvent,
  SessionEvent,
  AnyEvent,
} as const;

// Ensure output directory exists
mkdirSync(OUTPUT_DIR, { recursive: true });

for (const [name, schema] of Object.entries(schemas)) {
  const jsonSchema = z.toJSONSchema(schema, {
    target: "draft-07",
  });

  // Add title
  jsonSchema.title = name;

  const outputPath = join(OUTPUT_DIR, `${name}.json`);
  writeFileSync(outputPath, `${JSON.stringify(jsonSchema, null, 2)}\n`);
  console.log(`Generated: ${name}.json`);
}

console.log("\nJSON schema generation complete!");
