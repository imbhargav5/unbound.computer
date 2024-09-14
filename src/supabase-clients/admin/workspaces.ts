import { supabaseAdminClient } from './supabaseAdminClient';

export async function superAdminGetWorkspaceAdmins(workspaceId: string): Promise<string[]> {
  const { data, error } = await supabaseAdminClient
    .from('workspace_team_members')
    .select('*')
    .eq('workspace_id', workspaceId)
    .or('role.in.("admin","owner")');

  if (error) {
    throw error;
  }

  return data.map(({ user_profile_id }) => user_profile_id);
}
