import { supabaseUserClientComponent } from "@/supabase-clients/user/supabase-user-client-component";

export const getUserAvatarUrlClient = async (userId: string) => {
  const { data, error } = await supabaseUserClientComponent
    .from("user_profiles")
    .select("avatar_url")
    .eq("id", userId)
    .single();

  if (error) {
    throw error;
  }

  return data.avatar_url;
};

export const getUserFullNameClient = async (userId: string) => {
  const { data, error } = await supabaseUserClientComponent
    .from("user_profiles")
    .select("full_name")
    .eq("id", userId)
    .single();

  if (error) {
    throw error;
  }

  return data.full_name;
};
