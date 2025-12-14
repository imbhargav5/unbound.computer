"use server";
import { Unkey } from "@unkey/api";
import { z } from "zod";
import { authActionClient } from "@/lib/safe-action";
import { createSupabaseUserServerActionClient } from "@/supabase-clients/user/create-supabase-user-server-action-client";
import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/create-supabase-user-server-component-client";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";

const unkey = new Unkey({
  rootKey: process.env.UNKEY_ROOT_KEY,
});

function maskKey(key: string): string {
  const start = key.substr(0, 3);
  const end = key.substr(-3);
  const masked = "*".repeat(key.length - 6);
  return start + masked + end;
}

export const generateUnkeyTokenAction = authActionClient.action(
  async ({ ctx: { userId } }) => {
    const supabaseClient = await createSupabaseUserServerActionClient();
    const { data } = await unkey.keys.createKey({
      externalId: userId,
      apiId: process.env.UNKEY_API_ID,
      prefix: "st_",
    });

    const { key, keyId } = data;

    const { data: insertKeyResponse, error: insertKeyError } =
      await supabaseClient
        .from("user_api_keys")
        .insert({
          key_id: keyId,
          masked_key: maskKey(key),
          user_id: userId,
        })
        .select("*")
        .single();

    if (insertKeyError) {
      throw new Error(insertKeyError.message);
    }

    return {
      keyId,
      key,
      createdAt: insertKeyResponse.created_at,
    };
  }
);

const revokeUnkeyTokenSchema = z.object({
  keyId: z.string(),
});

export const revokeUnkeyTokenAction = authActionClient
  .inputSchema(revokeUnkeyTokenSchema)
  .action(async ({ parsedInput: { keyId } }) => {
    console.log("revoking key", keyId);
    try {
      await unkey.keys.deleteKey({
        keyId,
      });
    } catch (error) {
      throw error;
    }
    const supabaseClient = await createSupabaseUserServerActionClient();
    console.log("revoking key", keyId);
    const { error } = await supabaseClient
      .from("user_api_keys")
      .update({
        is_revoked: true,
      })
      .eq("key_id", keyId)
      .single();

    if (error) {
      throw new Error(error.message);
    }

    return { ok: true };
  });

export const getActiveDeveloperKeys = async () => {
  const user = await serverGetLoggedInUserClaims();
  const supabaseClient = await createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from("user_api_keys")
    .select("*")
    .eq("user_id", user.sub)
    .eq("is_revoked", false);

  if (error) {
    throw error;
  }
  return data;
};

export const getActiveDeveloperKeyCount = async () => {
  const user = await serverGetLoggedInUserClaims();
  const supabaseClient = await createSupabaseUserServerComponentClient();

  const { count, error } = await supabaseClient
    .from("user_api_keys")
    .select("*", { count: "exact", head: true })
    .eq("user_id", user.sub)
    .eq("is_revoked", false);

  if (error) {
    console.log(error);
    throw error;
  }
  return count ?? 0;
};

export const getRevokedApiKeyList = async () => {
  const supabaseClient = await createSupabaseUserServerComponentClient();
  const user = await serverGetLoggedInUserClaims();

  const { data, error } = await supabaseClient
    .from("user_api_keys")
    .select("*")
    .eq("user_id", user.sub)
    .eq("is_revoked", true);

  if (error) {
    throw error;
  }
  return data;
};
