import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';

export async function setOrganizationCredits(org_id: string, amount: number) {
  const { error, data } = await supabaseAdminClient
    .from('workspace_credits')
    .update({ credits: amount })
    .eq('organization_id', org_id)
    .select('*')
    .single();
  if (error) throw error;

  return data;
}
