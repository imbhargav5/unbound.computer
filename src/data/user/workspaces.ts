'use server';

import { RESTRICTED_SLUG_NAMES, SLUG_PATTERN } from '@/constants';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import { createSupabaseUserServerActionClient } from '@/supabase-clients/user/createSupabaseUserServerActionClient';
import { createSupabaseUserServerComponentClient } from '@/supabase-clients/user/createSupabaseUserServerComponentClient';
import type { Enum, SAPayload, Table } from '@/types';
import { serverGetLoggedInUser } from '@/utils/server/serverGetLoggedInUser';
import { revalidatePath } from 'next/cache';
import { v4 as uuid } from 'uuid';

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

export const createWorkspace = async (
    name: string,
    slug: string,
    workspaceType: Enum<'workspace_type'> = 'solo',
): Promise<SAPayload<string>> => {
    const supabaseClient = createSupabaseUserServerActionClient();
    const user = await serverGetLoggedInUser();
    const workspaceId = uuid();

    if (RESTRICTED_SLUG_NAMES.includes(slug)) {
        return { status: 'error', message: 'Slug is restricted' };
    }

    if (!SLUG_PATTERN.test(slug)) {
        return { status: 'error', message: 'Slug does not match the required pattern' };
    }

    const { error } = await supabaseClient.from('workspaces').insert({
        id: workspaceId,
        name,
        slug,
        workspace_type: workspaceType,
    });

    if (error) {
        return { status: 'error', message: error.message };
    }

    const { error: memberError } = await supabaseAdminClient
        .from('workspace_team_members')
        .insert({
            workspace_id: workspaceId,
            user_profile_id: user.id,
            role: 'owner',
        });

    if (memberError) {
        return { status: 'error', message: memberError.message };
    }

    revalidatePath(`/workspace/${slug}`, 'layout');

    return { status: 'success', data: slug };
};

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
    updates: Partial<Table<'workspaces'>>,
): Promise<SAPayload<Table<'workspaces'>>> => {
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
