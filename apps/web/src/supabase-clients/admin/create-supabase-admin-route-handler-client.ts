import { createClient } from "@supabase/supabase-js";
import type { Database } from "database/types";

/**
 * Creates a Supabase admin client for use in route handlers.
 * Uses the service role key to bypass RLS policies.
 *
 * SECURITY: Only use in server-side route handlers where admin access is required.
 * Never expose the service role key to the client.
 */
export const createSupabaseAdminRouteHandlerClient = async () => {
  return createClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }
  );
};
