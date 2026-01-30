import { createClient } from "@supabase/supabase-js";
import type { Database } from "database/types";
import type { NextRequest } from "next/server";

/**
 * Creates a Supabase client for mobile app requests.
 * Mobile apps (iOS) send their Supabase access token in the Authorization header.
 * This client uses that token directly for authentication.
 */
export function createSupabaseMobileClient(req: NextRequest) {
  const authHeader = req.headers.get("Authorization");

  if (!authHeader?.startsWith("Bearer ")) {
    throw new Error("Missing or invalid Authorization header");
  }

  const token = authHeader.split(" ")[1];

  const client = createClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    {
      global: {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      },
    }
  );

  return client;
}
