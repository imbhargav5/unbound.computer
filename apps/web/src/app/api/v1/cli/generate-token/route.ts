import { Unkey } from "@unkey/api";
import { type NextRequest, NextResponse } from "next/server";
import { createSupabaseUserRouteHandlerClient } from "@/supabase-clients/user/create-supabase-user-route-handler-client";

const unkey = new Unkey({
  rootKey: process.env.UNKEY_ROOT_KEY,
});

function maskKey(key: string): string {
  const start = key.substring(0, 3);
  const end = key.substring(key.length - 3);
  const masked = "*".repeat(key.length - 6);
  return start + masked + end;
}

/**
 * Generate a CLI-specific Unkey token for the authenticated user.
 * Called during `unbound link` after OAuth authentication.
 */
export async function POST(_req: NextRequest) {
  try {
    const supabaseClient = await createSupabaseUserRouteHandlerClient();
    const {
      data: { user },
      error: userError,
    } = await supabaseClient.auth.getUser();

    if (userError || !user) {
      return NextResponse.json(
        { error: "Unauthorized - please login first" },
        { status: 401 }
      );
    }

    const userId = user.id;

    // Create Unkey token with CLI-specific prefix and metadata
    const result = await unkey.keys.createKey({
      externalId: userId,
      apiId: process.env.UNKEY_API_ID!,
      prefix: "ub_cli",
      meta: {
        source: "cli",
        createdAt: new Date().toISOString(),
      },
    });

    const { key, keyId } = result.data;

    // Store masked key in database
    const { error: insertError } = await supabaseClient
      .from("user_api_keys")
      .insert({
        key_id: keyId,
        masked_key: maskKey(key),
        user_id: userId,
      });

    if (insertError) {
      return NextResponse.json({ error: insertError.message }, { status: 500 });
    }

    // Return the full key to the CLI (stored in OS keyring)
    return NextResponse.json({
      key,
      keyId,
      userId,
    });
  } catch (error) {
    return NextResponse.json({ error: String(error) }, { status: 500 });
  }
}
