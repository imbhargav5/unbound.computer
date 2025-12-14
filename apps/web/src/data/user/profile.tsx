"use server";

import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/create-supabase-user-server-component-client";

export const getUserAvatarUrl = async (userId: string) => {
  const supabase = await createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from("user_profiles")
    .select("avatar_url")
    .eq("id", userId)
    .single();

  if (error) {
    throw error;
  }

  return data.avatar_url;
};

export const getUserFullName = async (userId: string) => {
  const supabase = await createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from("user_profiles")
    .select("full_name")
    .eq("id", userId)
    .single();

  if (error) {
    throw error;
  }

  return data.full_name;
};
