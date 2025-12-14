import { createClient } from "@supabase/supabase-js";
import type { Database } from "database/types";

// A simple wrapper around the Supabase client that uses the service role key
// Suitable for scenarios where you don't have access to Next.js environment and just want to access
// the admin privileges
export const supabaseAdminClient = createClient<Database>(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SECRET_KEY,
  {
    global: {
      fetch,
    },
  }
);
