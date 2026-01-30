"use server";

import { createClient } from "@supabase/supabase-js";
import { Unkey } from "@unkey/api";
import type { Database } from "database/types";
import jwt from "jsonwebtoken";
import type { NextRequest } from "next/server";
import { z } from "zod";

const unkey = new Unkey({
  rootKey: process.env.UNKEY_ROOT_KEY,
});

function createJWT(userId: string) {
  const payload = {
    sub: userId,
    exp: Math.floor(Date.now() / 1000) + 60 * 60, // 1 hour expiry
    role: "authenticated",
    aud: "authenticated",
    iss: "https://ultimate-demo.usenextbase.com",
    iat: Math.floor(Date.now() / 1000) - 60,
  };

  const token = jwt.sign(payload, process.env.SUPABASE_JWT_SIGNING_KEY);
  return token;
}

const resultSchema = z.object({
  externalId: z.string(),
});

export async function createSupabaseUnkeyClient(req: NextRequest) {
  const authHeader = req.headers.get("Authorization");

  if (!(authHeader && authHeader.startsWith("Bearer "))) {
    throw new Error("Missing or invalid Authorization header");
  }

  const token = authHeader.split(" ")[1];

  const { data } = await unkey.keys.verifyKey({
    key: token,
  });
  if (data.code !== "VALID") {
    throw new Error(data.code);
  }

  const { externalId: userId } = resultSchema.parse(data.identity);

  const jwt = createJWT(userId);
  const client = createClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    {
      global: {
        headers: {
          Authorization: "Bearer " + jwt,
        },
      },
    }
  );

  return client;
}
