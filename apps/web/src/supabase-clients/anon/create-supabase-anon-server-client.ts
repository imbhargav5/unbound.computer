import { createServerClient } from "@supabase/ssr";
import type { Database } from "database/types";

/**
 * Creates an anonymous Supabase server client compatible with Next.js Cache Components.
 * This client does not use cookies and is safe to use within 'use cache' directives.
 *
 * Use this client in cached components/functions where you need to fetch public data
 * without user authentication.
 */
export const createSupabaseAnonServerClient = async () => {
  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    {
      cookies: {
        getAll() {
          return [];
        },
        setAll() {
          // no-op
        },
      },
      auth: {
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
    }
  );
};
