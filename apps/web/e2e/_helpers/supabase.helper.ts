import type { BrowserContext } from "@playwright/test";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "database/types";
import { userClaimsSchema } from "@/utils/zod-schemas/user-claims-schema";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabasePublishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
if (!(supabaseUrl && supabasePublishableKey)) {
  throw new Error("Supabase URL or publishable key is not set");
}
const supabaseClient = createClient<Database>(
  supabaseUrl,
  supabasePublishableKey
);

export async function getSupabaseClaims() {
  const { data, error } = await supabaseClient.auth.getClaims();
  if (error) {
    throw new Error(`Error getting claims: ${error.message}`);
  }
  if (!data) {
    throw new Error("No claims found");
  }
  return userClaimsSchema.parse(data.claims);
}

export async function getSupabaseClaimsFromContext(context: BrowserContext) {
  const cookies = await context.cookies();

  let combinedValue: string;

  // Check for single cookie first
  const singleCookie = cookies.find(
    (c) => c.name === "sb-localhost-auth-token"
  );

  if (singleCookie) {
    combinedValue = singleCookie.value;
  } else {
    // Auth token is chunked: sb-localhost-auth-token.0, sb-localhost-auth-token.1, etc.
    const authCookies = cookies
      .filter((c) => c.name.startsWith("sb-localhost-auth-token."))
      .sort((a, b) => {
        const aNum = Number.parseInt(a.name.split(".").pop() || "0");
        const bNum = Number.parseInt(b.name.split(".").pop() || "0");
        return aNum - bNum;
      });

    if (authCookies.length === 0) {
      throw new Error("No auth cookies found in context");
    }

    combinedValue = authCookies.map((c) => c.value).join("");
  }

  // Remove base64- prefix if present
  if (combinedValue.startsWith("base64-")) {
    combinedValue = combinedValue.slice(7);
  }

  const authData = JSON.parse(atob(combinedValue));

  if (!(supabaseUrl && supabasePublishableKey)) {
    throw new Error("Supabase URL or publishable key is not set");
  }
  const client = createClient<Database>(supabaseUrl, supabasePublishableKey);
  await client.auth.setSession({
    access_token: authData.access_token,
    refresh_token: authData.refresh_token,
  });

  const { data, error } = await client.auth.getClaims();
  if (error) throw new Error(`Error getting claims: ${error.message}`);
  if (!data) throw new Error("No claims found");
  return userClaimsSchema.parse(data.claims);
}
