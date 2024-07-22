'use server';
import { RESTRICTED_SLUG_NAMES, SLUG_PATTERN } from '@/constants';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import { createSupabaseUserServerActionClient } from '@/supabase-clients/user/createSupabaseUserServerActionClient';
import { createSupabaseUserServerComponentClient } from '@/supabase-clients/user/createSupabaseUserServerComponentClient';
import type {
  Enum,
  NormalizedSubscription,
  SAPayload,
  Table,
  UnwrapPromise,
} from '@/types';
import { serverGetLoggedInUser } from '@/utils/server/serverGetLoggedInUser';
import type { AuthUserMetadata } from '@/utils/zod-schemas/authUserMetadata';
import { revalidatePath } from 'next/cache';
import { v4 as uuid } from 'uuid';
import { refreshSessionAction } from './session';

export const getOrganizationIdBySlug = async (slug: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from('organizations')
    .select('*')
    .eq('slug', slug)
    .single();

  if (error) {
    throw error;
  }

  return data.id;
}

export const getOrganizationSlugByOrganizationId = async (organizationId: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const { data, error } = await supabaseClient
    .from('organizations')
    .select('slug')
    .eq('id', organizationId)
    .single();

  if (error) {
    throw error;
  }

  return data.slug;
}

export const createOrganization = async (
  name: string,
  slug: string,
  {
    isOnboardingFlow = false,
  }: {
    isOnboardingFlow?: boolean;
  } = {},
): Promise<SAPayload<string>> => {
  const supabaseClient = createSupabaseUserServerActionClient();
  const user = await serverGetLoggedInUser();

  const organizationId = uuid();

  if (RESTRICTED_SLUG_NAMES.includes(slug)) {
    return { status: 'error', message: 'Slug is restricted' };
  }

  if (!SLUG_PATTERN.test(slug)) {
    return { status: 'error', message: 'Slug does not match the required pattern' };
  }

  const { error, } = await supabaseClient.from('organizations').insert({
    title: name,
    id: organizationId,
    slug: slug
  });

  revalidatePath("/[organizationSlug]", 'layout');

  if (error) {
    return { status: 'error', message: error.message };
  }

  const { error: orgMemberErrors } = await supabaseAdminClient
    .from('organization_members')
    .insert([
      {
        member_id: user.id,
        organization_id: organizationId,
        member_role: 'owner',
      },
    ]);

  if (orgMemberErrors) {
    return { status: 'error', message: orgMemberErrors.message };
  }

  if (isOnboardingFlow) {

    // insert 3 dummy projects

    const { error: projectError } = await supabaseClient.from('projects').insert([
      {
        organization_id: organizationId,
        name: 'Project 1',
      },
      {
        organization_id: organizationId,
        name: 'Project 2',
      },
      {
        organization_id: organizationId,
        name: 'Project 3',
      },
    ]);

    if (projectError) {
      return { status: 'error', message: projectError.message };
    }

    const { error: updateError } = await supabaseClient
      .from('user_private_info')
      .update({ default_organization: organizationId })
      .eq('id', user.id);

    if (updateError) {
      return { status: 'error', message: updateError.message };
    }


    const updateUserMetadataPayload: Partial<AuthUserMetadata> = {
      onboardingHasCreatedOrganization: true,
    };

    const updateUserMetadataResponse = await supabaseClient.auth.updateUser({
      data: updateUserMetadataPayload,
    });

    if (updateUserMetadataResponse.error) {
      return {
        status: 'error',
        message: updateUserMetadataResponse.error.message,
      };
    }

    const refreshSessionResponse = await refreshSessionAction();
    if (refreshSessionResponse.status === 'error') {
      return refreshSessionResponse;
    }
  }

  return {
    status: 'success',
    data: slug,
  };
};

export async function fetchSlimOrganizations() {
  const currentUser = await serverGetLoggedInUser();
  const supabaseClient = createSupabaseUserServerComponentClient();
  const { data: organizations, error: organizationsError } =
    await supabaseClient
      .from('organization_members')
      .select('organization_id')
      .eq('member_id', currentUser.id);

  if (organizationsError) {
    throw organizationsError;
  }

  const { data, error } = await supabaseClient
    .from('organizations')
    .select('id,title,slug')
    .in(
      'id',
      organizations.map((org) => org.organization_id),
    )
    .order('created_at', {
      ascending: false,
    });
  if (error) {
    throw error;
  }

  return data || [];
}

export const getSlimOrganizationById = async (organizationId: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const { data, error } = await supabaseClient
    .from('organizations')
    .select('id,title')
    .eq('id', organizationId)
    .single();

  if (error) {
    throw error;
  }

  return data;
};

export const getAllOrganizationsForUser = async (userId: string) => {
  const supabase = createSupabaseUserServerComponentClient();
  const { data: organizations, error: organizationsError } = await supabase.rpc(
    'get_organizations_for_user',
    {
      user_id: userId,
    },
  );
  if (!organizations) {
    throw new Error(organizationsError.message);
  }

  const { data, error } = await supabase
    .from('organizations')
    .select(
      '*, organization_members(id,member_id,member_role, user_profiles(*)), subscriptions(id, prices(id,products(id,name)))',
    )
    .in(
      'id',
      organizations.map((org) => org.organization_id),
    )
    .order('created_at', {
      ascending: false,
    });
  if (error) {
    throw error;
  }

  return data || [];
};

export type InitialOrganizationListType = UnwrapPromise<
  ReturnType<typeof getAllOrganizationsForUser>
>;

export const getOrganizationById = async (organizationId: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from('organizations')
    // query team_members and team_invitations in one go
    .select('*')
    .eq('id', organizationId)
    .single();

  if (error) {
    throw error;
  }

  return data;
};

export const getOrganizationTitle = async (organizationId: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from('organizations')
    // query team_members and team_invitations in one go
    .select('id,title')
    .eq('id', organizationId)
    .single();

  if (error) {
    throw error;
  }

  return data.title;
};

export const getLoggedInUserOrganizationRole = async (
  organizationId: string,
): Promise<Enum<'organization_member_role'>> => {
  const { id: userId } = await serverGetLoggedInUser();
  const supabase = createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from('organization_members')
    .select('*')
    .eq('member_id', userId)
    .eq('organization_id', organizationId)
    .single();

  if (error) {
    throw error;
  } else if (!data) {
    throw new Error('User is not a member of this organization');
  }

  return data.member_role;
};

export const updateOrganizationInfo = async (
  organizationId: string,
  title: string,
  slug: string,
): Promise<SAPayload<Table<'organizations'>>> => {
  'use server';
  const supabase = createSupabaseUserServerActionClient();
  const { data, error } = await supabase
    .from('organizations')
    .update({
      title,
      slug,
    })
    .eq('id', organizationId)
    .select('*')
    .single();

  if (error) {
    return { status: 'error', message: error.message };
  }

  revalidatePath("/[organizationSlug]", 'layout');

  return { status: 'success', data };
};

export const getNormalizedOrganizationSubscription = async (
  organizationId: string,
): Promise<NormalizedSubscription> => {
  const supabase = createSupabaseUserServerComponentClient();
  const { data: subscriptions, error } = await supabase
    .from('subscriptions')
    .select('*, prices(*, products(*))')
    .eq('organization_id', organizationId)
    .in('status', ['trialing', 'active']);

  if (error) {
    throw error;
  }

  if (!subscriptions || subscriptions.length === 0) {
    return {
      type: 'no-subscription',
    };
  }

  try {
    const subscription = subscriptions[0];
    console.log(subscription);

    const price = Array.isArray(subscription.prices)
      ? subscription.prices[0]
      : subscription.prices;
    if (!price) {
      throw new Error('No price found');
    }

    const product = Array.isArray(price.products)
      ? price.products[0]
      : price.products;
    if (!product) {
      throw new Error('No product found');
    }

    if (subscription.status === 'trialing') {
      if (!subscription.trial_start || !subscription.trial_end) {
        throw new Error('No trial start or end found');
      }
      return {
        type: 'trialing',
        trialStart: subscription.trial_start,
        trialEnd: subscription.trial_end,
        product: product,
        price: price,
        subscription,
      };
    } else if (subscription.status) {
      return {
        type: subscription.status,
        product: product,
        price: price,
        subscription,
      };
    } else {
      return {
        type: 'no-subscription',
      };
    }
  } catch (err) {
    return {
      type: 'no-subscription',
    };
  }
};

export const getActiveProductsWithPrices = async () => {
  const supabase = createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from('products')
    .select('*, prices(*)')
    .eq('active', true)
    .eq('prices.active', true)
    .order('unit_amount', { foreignTable: 'prices' });

  if (error) {
    throw error;
  }

  return data || [];
};

export const getPendingInvitationsInOrganization = async (
  organizationId: string,
) => {
  const supabase = createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from('organization_join_invitations')
    .select(
      '*, inviter:user_profiles!inviter_user_id(*), invitee:user_profiles!invitee_user_id(*)',
    )
    .eq('organization_id', organizationId)
    .eq('status', 'active');

  if (error) {
    throw error;
  }

  return data || [];
};
export const getTeamMembersInOrganization = async (organizationId: string) => {
  const supabase = createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from('organization_members')
    .select('*, user_profiles(*)')
    .eq('organization_id', organizationId);

  if (error) {
    throw error;
  }

  return data.map((member) => {
    const { user_profiles, ...rest } = member;
    if (!user_profiles) {
      throw new Error('No user profile found for member');
    }
    return {
      ...rest,
      user_profiles: user_profiles,
    };
  });
};

export const getOrganizationAdmins = async (organizationId: string) => {
  const supabase = createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from('organization_members')
    .select('*, user_profiles(*)')
    .eq('organization_id', organizationId)
    .or('member_role.eq.admin,member_role.eq.owner');

  if (error) {
    throw error;
  }

  return data.map((member) => {
    const { user_profiles, ...rest } = member;
    if (!user_profiles) {
      throw new Error('No user profile found for member');
    }
    return {
      ...rest,
      user_profiles: user_profiles,
    };
  });
};

export const getDefaultOrganization = async () => {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const user = await serverGetLoggedInUser();
  const { data, error } = await supabaseClient
    .from('user_private_info')
    .select('id, default_organization')
    .eq('id', user.id)
    .single();

  if (error) {
    throw error;
  }

  return data.default_organization;
};

export const getDefaultOrganizationId = async () => {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const { data, error } = await supabaseClient
    .from('user_private_info')
    .select('default_organization')
    .single();

  if (error) {
    throw error;
  }

  if (!data.default_organization) {
    return null;
  }

  return data.default_organization;
};

export async function setDefaultOrganization(
  organizationId: string,
): Promise<SAPayload> {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const user = await serverGetLoggedInUser();

  const { error: updateError } = await supabaseClient
    .from('user_private_info')
    .update({ default_organization: organizationId })
    .eq('id', user.id);

  if (updateError) {
    return { status: 'error', message: updateError.message };
  }

  revalidatePath("/[organizationSlug]", 'layout');
  return { status: 'success' };
}

export async function deleteOrganization(
  organizationId: string,
): Promise<SAPayload<string>> {
  const supabaseClient = createSupabaseUserServerActionClient();
  const { error } = await supabaseClient
    .from('organizations')
    .delete()
    .eq('id', organizationId);

  if (error) {
    return { status: 'error', message: error.message };
  }

  revalidatePath("/[organizationSlug]", 'layout');
  return {
    status: 'success',
    data: `Organization ${organizationId} deleted successfully`,
  };
}



export const updateOrganizationSlug = async (
  organizationId: string,
  newSlug: string,
): Promise<SAPayload<string>> => {
  if (RESTRICTED_SLUG_NAMES.includes(newSlug)) {
    return { status: 'error', message: 'Slug is restricted' };
  }

  if (!SLUG_PATTERN.test(newSlug)) {
    return { status: 'error', message: 'Slug does not match the required pattern' };
  }

  const supabaseClient = createSupabaseUserServerActionClient();
  const { error } = await supabaseClient
    .from('organizations')
    .update({ slug: newSlug })
    .eq('id', organizationId);

  if (error) {
    return { status: 'error', message: error.message };
  }

  revalidatePath("/[organizationSlug]", 'layout');
  return { status: 'success', data: `Slug updated to ${newSlug}` };
};



/**
 * This is the organization that the user will be redirected to once they login
 * or when they go to the /dashboard page
 */
export async function getInitialOrganizationToRedirectTo(): Promise<SAPayload<string>> {
  const [slimOrganizations, defaultOrganizationId] = await Promise.all([
    fetchSlimOrganizations(),
    getDefaultOrganization(),
  ]);

  const firstOrganization = slimOrganizations[0];

  if (defaultOrganizationId) {
    const slug = await getOrganizationSlugByOrganizationId(defaultOrganizationId);
    return {
      data: slug,
      status: 'success',
    };
  }

  // this condition is unreachable as the parent ../layout component ensures at least
  // one organization exists
  if (!firstOrganization) {
    return {
      message: 'No organizations found',
      status: 'error',
    };
  }

  return {
    data: firstOrganization.slug,
    status: 'success',
  };
}

export async function getMaybeInitialOrganizationToRedirectTo(): Promise<SAPayload<string | null>> {

  const [slimOrganizations, defaultOrganizationId] = await Promise.all([
    fetchSlimOrganizations(),
    getDefaultOrganization(),
  ]);

  if (slimOrganizations.length === 0) {
    return {
      data: null,
      status: 'success',
    };
  } else if (defaultOrganizationId) {
    const slug = await getOrganizationSlugByOrganizationId(defaultOrganizationId);
    return {
      data: slug,
      status: 'success',
    };
  } else {
    return {
      data: slimOrganizations[0].slug,
      status: 'success',
    };
  }


}
