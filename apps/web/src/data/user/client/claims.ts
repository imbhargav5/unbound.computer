import { supabaseUserClientComponent } from "@/supabase-clients/user/supabase-user-client-component";

export const getClaims = async () => {
  const { data, error } = await supabaseUserClientComponent.auth.getClaims();
  if (error) throw error;
  if (!data?.claims) throw new Error("No claims found");
  return data.claims;
};
