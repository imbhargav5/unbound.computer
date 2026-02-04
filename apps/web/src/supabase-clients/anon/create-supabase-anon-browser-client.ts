import { createBrowserClient } from "@supabase/ssr";
import type { Database } from "database/types";

/**
 * Creates an anonymous Supabase browser client for use in client components.
 * Uses the anon/publishable key for public access.
 *
 * Use this client in "use client" components where you need to perform
 * authentication or access public data.
 */
export const createClient = () => {
  return createBrowserClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!
  );
};
