'use server';

import { Tables } from '@/lib/database.types';
import { authActionClient } from '@/lib/safe-action';
import { createSupabaseUserServerActionClient } from '@/supabase-clients/user/createSupabaseUserServerActionClient';
import { createSupabaseUserServerComponentClient } from '@/supabase-clients/user/createSupabaseUserServerComponentClient';
import type { DBTable, Enum, SAPayload } from '@/types';
import { serverGetLoggedInUser } from '@/utils/server/serverGetLoggedInUser';
import { AuthUserMetadata } from '@/utils/zod-schemas/authUserMetadata';
import { createWorkspaceSchema } from '@/utils/zod-schemas/workspaces';
import { revalidatePath } from 'next/cache';
import { v4 as uuid } from 'uuid';
import { addUserAsWorkspaceOwner, updateUserAppMetadata, updateWorkspaceMembershipType } from './elevatedQueries';
import { refreshSessionAction } from './session';


export const getWorkspaceIdBySlug = async (slug: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from('workspaces')
    .select('id')
    .eq('slug', slug)
    .single();

  if (error) {
    throw error;
  }

  return data.id;
};

export const getWorkspaceSlugById = async (workspaceId: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from('workspaces')
    .select('slug')
    .eq('id', workspaceId)
    .single();

  if (error) {
    throw error;
  }

  return data.slug;
};



export const createWorkspace = authActionClient.schema(createWorkspaceSchema).action(
  async ({
    parsedInput: {
      name,
      slug,
      workspaceType,
      isOnboardingFlow
    },
    ctx: {
      userId
    }
  }) => {
    const workspaceId = uuid();
    const supabaseClient = createSupabaseUserServerActionClient();
    const { error } = await supabaseClient.from('workspaces').insert({
      id: workspaceId,
      name,
      slug: slug ?? workspaceId,
    });

    if (error) {
      throw new Error(error.message);
    }

    await Promise.all([
      addUserAsWorkspaceOwner({ workspaceId, userId }),
      updateWorkspaceMembershipType({ workspaceId, workspaceMembershipType: workspaceType })
    ]);

    if (isOnboardingFlow) {
      // Create dummy projects
      const { error: projectError } = await supabaseClient.from('projects').insert([
        { workspace_id: workspaceId, name: 'Project 1' },
        { workspace_id: workspaceId, name: 'Project 2' },
        { workspace_id: workspaceId, name: 'Project 3' },
      ]);

      if (projectError) {
        console.error('Error creating projects', projectError);
        throw new Error(projectError.message);
      }

      console.log('Creating default workspace for user', userId);

      // Set default workspace for the user
      const { error: updateError } = await supabaseClient
        .from('user_settings')
        .update({
          default_workspace: workspaceId
        })
        .eq('id', userId);

      if (updateError) {
        console.error('Error setting default workspace', updateError);
        throw new Error(updateError.message);
      }

      // Update user metadata
      const updateUserMetadataPayload: Partial<AuthUserMetadata> = {
        onboardingHasCreatedWorkspace: true,
      };

      await updateUserAppMetadata({
        userId,
        appMetadata: updateUserMetadataPayload
      });


      console.log('refreshing session');
      // Refresh the session
      await refreshSessionAction();
      console.log('refreshed session');
    }



    if (workspaceType === 'team') {

      revalidatePath(`/workspace/${slug}`, 'layout');
    } else {
      revalidatePath(`/`, 'layout');
    }

    return slug;
  }
);

export const getWorkspaceById = async (workspaceId: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from('workspaces')
    .select('*')
    .eq('id', workspaceId)
    .single();

  if (error) {
    throw error;
  }

  return data;
};

export const getWorkspaceTeamMembers = async (workspaceId: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from('workspace_team_members')
    .select('*, user_profiles(*)')
    .eq('workspace_id', workspaceId);

  if (error) {
    throw error;
  }

  return data;
};

export const getWorkspaceInvitations = async (workspaceId: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from('workspace_invitations')
    .select('*')
    .eq('workspace_id', workspaceId)
    .eq('status', 'active');

  if (error) {
    throw error;
  }

  return data;
};

export const updateWorkspace = async (
  workspaceId: string,
  updates: Partial<DBTable<'workspaces'>>,
): Promise<SAPayload<DBTable<'workspaces'>>> => {
  const supabaseClient = createSupabaseUserServerActionClient();

  const { data, error } = await supabaseClient
    .from('workspaces')
    .update(updates)
    .eq('id', workspaceId)
    .select()
    .single();

  if (error) {
    return { status: 'error', message: error.message };
  }

  revalidatePath(`/workspace/${data.slug}`, 'layout');

  return { status: 'success', data };
};

export const deleteWorkspace = async (workspaceId: string): Promise<SAPayload<string>> => {
  const supabaseClient = createSupabaseUserServerActionClient();

  const { error } = await supabaseClient
    .from('workspaces')
    .delete()
    .eq('id', workspaceId);

  if (error) {
    return { status: 'error', message: error.message };
  }

  revalidatePath('/workspaces', 'layout');

  return { status: 'success', data: `Workspace ${workspaceId} deleted successfully` };
};

export const getWorkspaceCredits = async (workspaceId: string): Promise<number> => {
  const supabaseClient = createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from('workspace_credits')
    .select('credits')
    .eq('workspace_id', workspaceId)
    .single();

  if (error) {
    throw error;
  }

  return data.credits;
};

export const updateWorkspaceCredits = async (
  workspaceId: string,
  newCredits: number,
): Promise<SAPayload<number>> => {
  const supabaseClient = createSupabaseUserServerActionClient();

  const { data, error } = await supabaseClient
    .from('workspace_credits')
    .update({ credits: newCredits })
    .eq('workspace_id', workspaceId)
    .select('credits')
    .single();

  if (error) {
    return { status: 'error', message: error.message };
  }

  return { status: 'success', data: data.credits };
};

export const getWorkspaceCreditsLogs = async (workspaceId: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from('workspace_credits_logs')
    .select('*')
    .eq('workspace_id', workspaceId)
    .order('changed_at', { ascending: false });

  if (error) {
    throw error;
  }

  return data;
};

export async function getMaybeDefaultWorkspace(): Promise<{
  workspace: Tables<'workspaces'>,
  workspaceMembershipType: Enum<'workspace_membership_type'>
} | null> {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const user = await serverGetLoggedInUser();


  // Check for solo workspace
  const [workspaceListResponse, userSettingsResponse] = await Promise.all([
    supabaseClient
      .from('workspaces')
      .select('*, workspace_application_settings(*)'),
    supabaseClient
      .from('user_settings')
      .select('*')
      .eq('id', user.id)
      .single()
  ]);


  const { data: workspaceList, error: workspaceListError } = workspaceListResponse;

  if (workspaceListError) {
    throw workspaceListError;
  }

  if (Array.isArray(workspaceList) && workspaceList.length > 0) {
    // if there is a solo workspace or a default workspace
    // Check for default workspace in user settings

    const { data: userSettings, error: settingsError } = userSettingsResponse;

    if (settingsError && settingsError.code !== 'PGRST116') {
      throw settingsError;
    }
    const defaultWorkspace = workspaceList.find((workspace) => workspace.id === userSettings?.default_workspace);
    // if a default workspace is set, return it
    if (defaultWorkspace) {
      return {
        workspace: defaultWorkspace,
        workspaceMembershipType: defaultWorkspace.workspace_application_settings?.membership_type ?? 'solo'
      };
    } else {
      return {
        workspace: workspaceList[0],
        workspaceMembershipType: workspaceList[0].workspace_application_settings?.membership_type ?? 'solo'
      };
    }
  } else {
    return null;
  }

}



export async function fetchSlimWorkspaces() {
  const currentUser = await serverGetLoggedInUser();
  const supabaseClient = createSupabaseUserServerComponentClient();

  const { data: workspaceMembers, error: membersError } = await supabaseClient
    .from('workspace_team_members')
    .select('workspace_id')
    .eq('user_profile_id', currentUser.id);

  if (membersError) {
    console.error("fetchSlimWorkspaces workspaceMembers", membersError);
    throw membersError;
  }

  const { data, error } = await supabaseClient
    .from('workspaces')
    .select('id,name,slug')
    .in(
      'id',
      workspaceMembers.map((member) => member.workspace_id),
    )
    .order('created_at', {
      ascending: false,
    });

  if (error) {
    console.error("fetchSlimWorkspaces workspaceMembers", error);
    throw error;
  }

  return data || [];
}

export async function setDefaultWorkspace(
  workspaceId: string
): Promise<string> {
  const supabaseClient = createSupabaseUserServerActionClient();
  const user = await serverGetLoggedInUser();

  const { error } = await supabaseClient
    .from('user_settings')
    .upsert({
      id: user.id,
      default_workspace: workspaceId
    }, {
      onConflict: 'id'
    });

  if (error) {
    throw error;
  }

  return workspaceId;
}
