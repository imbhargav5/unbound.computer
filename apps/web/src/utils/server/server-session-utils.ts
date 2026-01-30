"use server";
import { cache } from "react";
import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/create-supabase-user-server-component-client";
import { userClaimsSchema } from "../zod-schemas/user-claims-schema";

export const getUser = cache(async () => {
  const supabase = await createSupabaseUserServerComponentClient();
  return await supabase.auth.getUser();
});

export const getClaims = cache(async () => {
  const supabase = await createSupabaseUserServerComponentClient();
  const { data, error } = await supabase.auth.getClaims();
  if (error) {
    throw error;
  }
  if (!data) {
    throw new Error("getClaims: No data");
  }
  return userClaimsSchema.parse(data.claims);
});
