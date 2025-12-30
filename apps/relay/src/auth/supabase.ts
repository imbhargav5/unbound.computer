import { createClient } from "@supabase/supabase-js";
import { config } from "../config.js";

/**
 * Supabase admin client with service role key
 * Used for server-side operations like validating device tokens
 */
export const supabaseAdmin = createClient(
  config.SUPABASE_URL,
  config.SUPABASE_SERVICE_ROLE_KEY
);
