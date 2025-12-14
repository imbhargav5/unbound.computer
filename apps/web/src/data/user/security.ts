"use server";
import { z } from "zod";
import { authActionClient } from "@/lib/safe-action";
import { createSupabaseUserServerActionClient } from "@/supabase-clients/user/create-supabase-user-server-action-client";

const updatePasswordSchema = z.object({
  password: z.string().min(4),
});

export const updatePasswordAction = authActionClient
  .inputSchema(updatePasswordSchema)
  .action(async ({ parsedInput: { password } }) => {
    const supabaseClient = await createSupabaseUserServerActionClient();
    const { error } = await supabaseClient.auth.updateUser({
      password,
    });

    if (error) {
      throw new Error(error.message);
    }
  });

const updateEmailSchema = z.object({
  email: z.email(),
});

export const updateEmailAction = authActionClient
  .inputSchema(updateEmailSchema)
  .action(async ({ parsedInput: { email } }) => {
    const supabaseClient = await createSupabaseUserServerActionClient();
    const { error } = await supabaseClient.auth.updateUser({
      email,
    });

    if (error) {
      throw new Error(error.message);
    }

    // Return void if successful
  });
