'use server';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import { SlimWorkspaces } from '@/types';
import { ensureAppAdmin } from './security';

export async function getWorkspacesTotalPages({
  query = '',
  limit = 10,
}: {
  query?: string;
  limit?: number;
}) {
  ensureAppAdmin();
  const { count, error } = await supabaseAdminClient.from('workspaces').select('id', {
    count: 'exact',
    head: true,
  }).ilike('name', `%${query}%`);
  if (error) throw error;
  if (!count) throw new Error('No count');
  return Math.ceil(count / limit);
}

export async function getPaginatedWorkspaceList({
  limit = 10,
  page = 1,
  query = undefined,
}: {
  page?: number;
  query?: string | undefined;
  limit?: number;
}) {
  ensureAppAdmin();
  let requestQuery = supabaseAdminClient.from('workspaces').select('*');
  if (query) {
    requestQuery = requestQuery.ilike('name', `%${query}%`);
  }
  const { data, error } = await requestQuery.range((page - 1) * limit, page * limit);
  if (error) throw error;
  if (!data) {
    throw new Error('No data');
  }
  return data;
}

export async function getSlimWorkspacesOfUser(userId: string): Promise<SlimWorkspaces> {

  const { data: workspaceTeamMembers, error: workspaceTeamMembersError } =
    await supabaseAdminClient
      .from('workspace_team_members')
      .select('*')
      .eq('member_id', userId);

  if (workspaceTeamMembersError) {
    throw workspaceTeamMembersError;
  }


  const { data, error } = await supabaseAdminClient
    .from('workspaces')
    .select('id,name,slug,workspace_application_settings(*)')
    .in('id', workspaceTeamMembers.map((member) => member.workspace_id))
    .order('created_at', {
      ascending: false,
    });
  if (error) {
    throw error;
  }

  return data.map((workspace) => {
    return {
      id: workspace.id,
      name: workspace.name,
      slug: workspace.slug,
      membershipType: workspace.workspace_application_settings?.membership_type ?? 'solo',
    };
  });
}
