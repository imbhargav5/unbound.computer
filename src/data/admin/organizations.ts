'use server';
import { adminActionClient } from '@/lib/safe-action';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import { SlimWorkspaces } from '@/types';
import { z } from 'zod';
import { ensureAppAdmin } from './security';

const getWorkspacesTotalPagesSchema = z.object({
  query: z.string().optional().default(''),
  limit: z.number().optional().default(10),
});

export const getWorkspacesTotalPagesAction = adminActionClient
  .schema(getWorkspacesTotalPagesSchema)
  .action(async ({ parsedInput: { query, limit } }) => {
    ensureAppAdmin();
    const { count, error } = await supabaseAdminClient.from('workspaces').select('id', {
      count: 'exact',
      head: true,
    }).ilike('name', `%${query}%`);
    if (error) throw error;
    if (!count) throw new Error('No count');
    return Math.ceil(count / limit);
  });

const getPaginatedWorkspaceListSchema = z.object({
  page: z.number().optional().default(1),
  query: z.string().optional(),
  limit: z.number().optional().default(10),
});

export const getPaginatedWorkspaceListAction = adminActionClient
  .schema(getPaginatedWorkspaceListSchema)
  .action(async ({ parsedInput: { page, query, limit } }) => {
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
  });

const getSlimWorkspacesOfUserSchema = z.object({
  userId: z.string(),
});

export const getSlimWorkspacesOfUserAction = adminActionClient
  .schema(getSlimWorkspacesOfUserSchema)
  .action(async ({ parsedInput: { userId } }): Promise<SlimWorkspaces> => {
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

    return data.map((workspace) => ({
      id: workspace.id,
      name: workspace.name,
      slug: workspace.slug,
      membershipType: workspace.workspace_application_settings?.membership_type ?? 'solo',
    }));
  });
