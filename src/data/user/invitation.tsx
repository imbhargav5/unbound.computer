"use server";
import type { Tables } from "@/lib/database.types";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabaseAdminClient";
import { createSupabaseUserServerActionClient } from "@/supabase-clients/user/createSupabaseUserServerActionClient";
import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/createSupabaseUserServerComponentClient";
import type { Enum, SAPayload } from "@/types";
import { sendEmail } from "@/utils/api-routes/utils";
import { toSiteURL } from "@/utils/helpers";
import { serverGetLoggedInUser } from "@/utils/server/serverGetLoggedInUser";
import { renderAsync } from "@react-email/render";
import TeamInvitationEmail from "emails/TeamInvitation";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { getInvitationOrganizationDetails } from "./elevatedQueries";
import {
  createAcceptedWorkspaceInvitationNotification,
  createNotification,
} from "./notifications";
import { getUserProfile } from "./user";
import { getWorkspaceById } from "./workspaces";

// This function allows an application admin with service_role
// to check if a user with a given email exists in the auth.users table
export const appAdminGetUserIdByEmail = async (
  email: string,
): Promise<string | null> => {
  const { data, error } = await supabaseAdminClient.rpc(
    "app_admin_get_user_id_by_email",
    {
      emailarg: email,
    },
  );

  if (error) {
    throw error;
  }

  return data;
};

async function setupInviteeUserDetails(email: string): Promise<{
  type: "USER_CREATED" | "USER_EXISTS";
  userId: string;
}> {
  const inviteeUserId = await appAdminGetUserIdByEmail(email);
  if (!inviteeUserId) {
    const { data, error } = await supabaseAdminClient.auth.admin.createUser({
      email: email,
    });
    if (error) {
      throw error;
    }
    return {
      type: "USER_CREATED",
      userId: data.user.id,
    };
  }

  return {
    type: "USER_EXISTS",
    userId: inviteeUserId,
  };
}

async function getMagicLink(email: string): Promise<string> {
  const response = await supabaseAdminClient.auth.admin.generateLink({
    email,
    type: "magiclink",
  });

  if (response.error) {
    throw response.error;
  }

  const generateLinkData = response.data;

  if (generateLinkData) {
    const {
      properties: { hashed_token },
    } = generateLinkData;

    if (process.env.NEXT_PUBLIC_SITE_URL !== undefined) {
      // change the origin of the link to the site url

      const tokenHash = hashed_token;
      const searchParams = new URLSearchParams({
        token_hash: tokenHash,
        next: "/dashboard",
      });

      const url = new URL(process.env.NEXT_PUBLIC_SITE_URL);
      url.pathname = `/auth/confirm`;
      url.search = searchParams.toString();

      return url.toString();
    } else {
      throw new Error("Site URL is not defined");
    }
  } else {
    throw new Error("No data returned");
  }
}

async function getViewInvitationUrl(
  invitationId: string,
  inviteeDetails: {
    type: "USER_CREATED" | "USER_EXISTS";
    userId: string;
  },
  email: string,
): Promise<string> {
  if (inviteeDetails.type === "USER_CREATED") {
    const magicLink = await getMagicLink(email);
    return magicLink;
  }

  return toSiteURL("/api/invitations/view/" + invitationId);
}

export async function createInvitationHandler({
  organizationId,
  email,
  role,
}: {
  organizationId: string;
  email: string;
  role: Enum<"organization_member_role">;
}): Promise<SAPayload<Tables<"workspace_invitations">>> {
  "use server";
  const supabaseClient = createSupabaseUserServerActionClient();
  const user = await serverGetLoggedInUser();
  // check if organization exists
  const organizationResponse = await supabaseClient
    .from("workspaces")
    .select("*")
    .eq("id", organizationId)
    .single();

  if (organizationResponse.error) {
    return { status: 'error', message: organizationResponse.error.message };
  }

  const inviteeUserDetails = await setupInviteeUserDetails(email);
  // check if already invited
  const existingInvitationResponse = await supabaseClient
    .from("workspace_invitations")
    .select("*")
    .eq("invitee_user_id", inviteeUserDetails.userId)
    .eq("inviter_user_id", user.id)
    .eq("status", "active")
    .eq("organization_id", organizationId);

  if (existingInvitationResponse.error) {
    return { status: 'error', message: existingInvitationResponse.error.message };
  } if (existingInvitationResponse.data.length > 0) {
    return { status: 'error', message: 'User already invited' };
  }

  const invitationResponse = await supabaseClient
    .from("workspace_invitations")
    .insert({
      invitee_user_email: email,
      invitee_user_id: inviteeUserDetails.userId,
      inviter_user_id: user.id,
      status: "active",
      workspace_id: organizationId,
      invitee_workspace_role: role,
    })
    .select("*")
    .single();

  if (invitationResponse.error) {
    return { status: 'error', message: invitationResponse.error.message };
  }

  const viewInvitationUrl = await getViewInvitationUrl(
    invitationResponse.data.id,
    inviteeUserDetails,
    email,
  );

  const userProfileData = await supabaseClient
    .from("user_profiles")
    .select("*")
    .eq("id", user.id)
    .single();

  if (userProfileData.error) {
    return { status: 'error', message: userProfileData.error.message };
  }

  const inviterName = userProfileData.data?.full_name || `User [${user.email}]`;

  // send email
  const invitationEmailHTML = await renderAsync(
    <TeamInvitationEmail
      viewInvitationUrl={viewInvitationUrl}
      inviterName={`${inviterName}`}
      isNewUser={inviteeUserDetails.type === "USER_CREATED"}
      organizationName={organizationResponse.data.name}
    />,
  );

  await sendEmail({
    to: email,
    subject: `Invitation to join ${organizationResponse.data.name}`,
    html: invitationEmailHTML,
    from: process.env.ADMIN_EMAIL,
  });

  // send notification
  await createNotification(inviteeUserDetails.userId, {
    inviterFullName: inviterName,
    organizationId: organizationId,
    organizationName: organizationResponse.data.name,
    invitationId: invitationResponse.data.id,
  });

  revalidatePath("/[organizationSlug]/settings/members", "layout");

  return { status: 'success', data: invitationResponse.data };
}

export async function acceptInvitationAction(
  invitationId: string,
): Promise<SAPayload<string>> {
  "use server";
  const supabaseClient = createSupabaseUserServerActionClient();
  const user = await serverGetLoggedInUser();

  const invitationResponse = await supabaseClient
    .from("workspace_invitations")
    .update({
      status: "finished_accepted",
      invitee_user_id: user.id, // Add this information here, so that our database function can add this id to the team members table
    })
    .eq("id", invitationId)
    .select("*")
    .single();

  if (invitationResponse.error) {
    return { status: 'error', message: invitationResponse.error.message };
  }

  const userProfile = await getUserProfile(user.id);

  await createAcceptedWorkspaceInvitationNotification(
    invitationResponse.data?.inviter_user_id,
    {
      workspaceId: invitationResponse.data.workspace_id,
      inviteeFullName: userProfile.full_name ?? `User ${userProfile.id}`,
    },
  );

  revalidatePath("/", "layout");
  const workspace = await getWorkspaceById(invitationResponse.data.workspace_id);
  return { status: 'success', data: workspace.slug };
}

export async function declineInvitationAction(invitationId: string): Promise<SAPayload> {
  "use server";
  const supabaseClient = createSupabaseUserServerActionClient();
  const user = await serverGetLoggedInUser();

  const invitationResponse = await supabaseClient
    .from("workspace_invitations")
    .update({
      status: "finished_declined",
      invitee_user_id: user.id, // Add this information here, so that our database function can add this id to the team members table
    })
    .eq("id", invitationId)
    .select("*")
    .single();

  if (invitationResponse.error) {
    return { status: 'error', message: invitationResponse.error.message };
  }

  revalidatePath("/", "layout");
  redirect("/dashboard");
}

export async function getPendingInvitationsOfUser() {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const user = await serverGetLoggedInUser();
  const { data, error } = await supabaseClient
    .from("workspace_invitations")
    .select(
      "*, inviter:user_profiles!inviter_user_id(*), invitee:user_profiles!invitee_user_id(*), workspace:workspaces(*)",
    )
    .eq("invitee_user_id", user.id)
    .eq("status", "active");

  if (error) {
    throw error;
  }

  const invitationListPromise = data.map(async (invitation) => {
    const workspace = await getInvitationOrganizationDetails(
      invitation.workspace_id,
    );
    return {
      ...invitation,
      workspace,
    };
  });

  return Promise.all(invitationListPromise);
}

export const getInvitationById = async (invitationId: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();

  const { data, error } = await supabaseClient
    .from("workspace_invitations")
    .select(
      "*, inviter:user_profiles!inviter_user_id(*), invitee:user_profiles!invitee_user_id(*), workspace:workspaces(*)",
    )
    .eq("id", invitationId)
    .eq("status", "active")
    .single();

  if (error) {
    throw error;
  }

  const workspaceId = data.workspace_id;

  const workspace = await getInvitationOrganizationDetails(workspaceId);

  return {
    ...data,
    workspace,
  };
};

export async function getPendingInvitationCountOfUser() {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const user = await serverGetLoggedInUser();

  async function idInvitations(userId: string) {
    const { count, error } = await supabaseClient
      .from("workspace_invitations")
      .select("id", { count: "exact", head: true })
      .eq("invitee_user_id", userId)
      .eq("status", "active");

    if (error) {
      throw error;
    }

    return count || 0;
  }

  const idInvitationsCount = await idInvitations(user.id);

  return idInvitationsCount;
}

export async function revokeInvitation(invitationId: string): Promise<SAPayload<Tables<"workspace_invitations">>> {
  "use server";
  const supabaseClient = createSupabaseUserServerActionClient();

  const invitationResponse = await supabaseClient
    .from("workspace_invitations")
    .delete()
    .eq("id", invitationId)
    .single();

  if (invitationResponse.error) {
    return { status: 'error', message: invitationResponse.error.message };
  }

  revalidatePath("/", "layout");

  return { status: 'success', data: invitationResponse.data };
}
