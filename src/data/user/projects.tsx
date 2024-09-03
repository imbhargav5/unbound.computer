"use server";
import { CommentList } from "@/components/Projects/CommentList";
import type { Tables } from "@/lib/database.types";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabaseAdminClient";
import { createSupabaseUserServerActionClient } from "@/supabase-clients/user/createSupabaseUserServerActionClient";
import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/createSupabaseUserServerComponentClient";
import type { CommentWithUser, SAPayload } from "@/types";
import { normalizeComment } from "@/utils/comments";
import { serverGetLoggedInUser } from "@/utils/server/serverGetLoggedInUser";
import { revalidatePath } from "next/cache";
import { Suspense } from "react";

export async function getSlimProjectById(projectId: string) {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .select("id,name,project_status,organization_id,slug")
    .eq("id", projectId)
    .single();
  if (error) {
    throw error;
  }
  return data;
}

export const getSlimProjectBySlug = async (projectSlug: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .select("id, slug, name")
    .eq("slug", projectSlug)
    .single();
  if (error) {
    throw error;
  }
  return data;
}

export async function getProjectById(projectId: string) {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .select("*")
    .eq("id", projectId)
    .single();
  if (error) {
    throw error;
  }
  return data;
}

export async function getProjectTitleById(projectId: string) {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .select("name")
    .eq("id", projectId)
    .single();
  if (error) {
    throw error;
  }
  return data.name;
}

export const createProjectAction = async ({
  workspaceId,
  name,
  slug,
}: {
  workspaceId: string;
  name: string;
  slug: string;
}): Promise<SAPayload<Tables<"projects">>> => {
  "use server";
  const supabaseClient = createSupabaseUserServerActionClient();
  const { data: project, error } = await supabaseClient
    .from("projects")
    .insert({
      workspace_id: workspaceId,
      name,
      slug,
    })
    .select("*")
    .single();


  if (error) {
    return {
      status: 'error',
      message: error.message,
    };
  }


  revalidatePath("/[organizationSlug]", "layout");
  revalidatePath("/[organizationSlug]/projects", "layout");

  return {
    status: 'success',
    data: project,
  };
};

export const getProjectComments = async (
  projectId: string,
): Promise<Array<CommentWithUser>> => {
  const supabase = createSupabaseUserServerComponentClient();
  const { data, error } = await supabase
    .from("project_comments")
    .select("*, user_profiles(*)")
    .eq("project_id", projectId)
    .order("created_at", { ascending: false });
  if (error) {
    throw error;
  }

  return data.map(normalizeComment);
};

export const createProjectCommentAction = async (
  projectId: string,
  text: string,
): Promise<SAPayload<{ id: number, commentList: React.JSX.Element }>> => {
  const supabaseClient = createSupabaseUserServerActionClient();
  const user = await serverGetLoggedInUser();
  const { data, error } = await supabaseClient
    .from("project_comments")
    .insert({ project_id: projectId, text, user_id: user.id })
    .select("*, user_profiles(*)")
    .single();
  if (error) {
    return { status: 'error', message: error.message };
  }
  revalidatePath(`/project/${projectId}`, "page");

  return {
    status: 'success',
    data: {
      id: data.id,
      commentList: (
        <Suspense>
          <CommentList comments={[normalizeComment(data)]} />
        </Suspense>
      ),
    },
  };
};

export const approveProjectAction = async (projectId: string): Promise<SAPayload<Tables<"projects">>> => {
  const supabaseClient = createSupabaseUserServerActionClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .update({ project_status: "approved" })
    .eq("id", projectId)
    .select("*")
    .single();

  if (error) {
    return { status: 'error', message: error.message };
  }

  revalidatePath(`/project/${projectId}`, "layout");
  return { status: 'success', data };
};

export const rejectProjectAction = async (projectId: string): Promise<SAPayload<Tables<"projects">>> => {
  const supabaseClient = createSupabaseUserServerActionClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .update({ project_status: "draft" })
    .eq("id", projectId)
    .select("*")
    .single();

  if (error) {
    return { status: 'error', message: error.message };
  }

  revalidatePath(`/project/${projectId}`, "layout");
  return { status: 'success', data };
};

export const submitProjectForApprovalAction = async (
  projectId: string,
): Promise<SAPayload<Tables<"projects">>> => {
  const supabaseClient = createSupabaseUserServerActionClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .update({ project_status: "pending_approval" })
    .eq("id", projectId)
    .select("*")
    .single();

  if (error) {
    return { status: "error", message: error.message };
  }

  revalidatePath(`/project/${projectId}`, "layout");
  return { status: "success", data };
};

export const markProjectAsCompletedAction = async (projectId: string): Promise<SAPayload<Tables<"projects">>> => {
  const supabaseClient = createSupabaseUserServerActionClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .update({ project_status: "completed" })
    .eq("id", projectId)
    .select("*")
    .single();

  if (error) {
    return { status: 'error', message: error.message };
  }

  revalidatePath(`/project/${projectId}`, "layout");
  return { status: 'success', data };
};

export const getProjects = async ({
  organizationId,
  query = "",
  page = 1,
  limit = 5,
}: {
  query?: string;
  page?: number;
  organizationId: string;
  limit?: number;
}) => {
  const zeroIndexedPage = page - 1;
  const supabase = createSupabaseUserServerComponentClient();
  let supabaseQuery = supabase
    .from("projects")
    .select("*")
    .eq("organization_id", organizationId)
    .range(zeroIndexedPage * limit, (zeroIndexedPage + 1) * limit - 1);

  if (query) {
    supabaseQuery = supabaseQuery.ilike("name", `%${query}%`);
  }

  const { data, error } = await supabaseQuery.order("created_at", {
    ascending: false,
  });

  if (error) {
    throw error;
  }

  return data;
};

export const getProjectsTotalCount = async ({
  organizationId,
  query = "",
  page = 1,
  limit = 5,
}: {
  organizationId: string;
  query?: string;
  page?: number;
  limit?: number;
}) => {
  const zeroIndexedPage = page - 1;
  let supabaseQuery = supabaseAdminClient
    .from("projects")
    .select("id", {
      count: "exact",
      head: true,
    })
    .eq("organization_id", organizationId)
    .range(zeroIndexedPage * limit, (zeroIndexedPage + 1) * limit - 1);

  if (query) {
    supabaseQuery = supabaseQuery.ilike("name", `%${query}%`);
  }

  const { count, error } = await supabaseQuery.order("created_at", {
    ascending: false,
  });

  if (error) {
    throw error;
  }

  if (!count) {
    return 0;
  }

  return Math.ceil(count / limit) ?? 0;
};

export async function getSlimProjectByIdForWorkspace(projectId: string) {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .select("id,name,project_status,workspace_id,slug")
    .eq("id", projectId)
    .single();
  if (error) {
    throw error;
  }
  return data;
}

export const getSlimProjectBySlugForWorkspace = async (projectSlug: string) => {
  const supabaseClient = createSupabaseUserServerComponentClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .select("id, slug, name")
    .eq("slug", projectSlug)
    .single();
  if (error) {
    throw error;
  }
  return data;
}

export const createProjectActionForWorkspace = async ({
  workspaceId,
  name,
  slug,
}: {
  workspaceId: string;
  name: string;
  slug: string;
}): Promise<SAPayload<Tables<"projects">>> => {
  "use server";
  const supabaseClient = createSupabaseUserServerActionClient();
  const { data: project, error } = await supabaseClient
    .from("projects")
    .insert({
      workspace_id: workspaceId,
      name,
      slug,
    })
    .select("*")
    .single();

  if (error) {
    return {
      status: 'error',
      message: error.message,
    };
  }

  revalidatePath("/[workspaceSlug]", "layout");
  revalidatePath("/[workspaceSlug]/projects", "layout");

  return {
    status: 'success',
    data: project,
  };
};

export const getProjectsForWorkspace = async ({
  workspaceId,
  query = "",
  page = 1,
  limit = 5,
}: {
  query?: string;
  page?: number;
  workspaceId: string;
  limit?: number;
}) => {
  const zeroIndexedPage = page - 1;
  const supabase = createSupabaseUserServerComponentClient();
  let supabaseQuery = supabase
    .from("projects")
    .select("*")
    .eq("workspace_id", workspaceId)
    .range(zeroIndexedPage * limit, (zeroIndexedPage + 1) * limit - 1);

  if (query) {
    supabaseQuery = supabaseQuery.ilike("name", `%${query}%`);
  }

  const { data, error } = await supabaseQuery.order("created_at", {
    ascending: false,
  });

  if (error) {
    throw error;
  }

  return data;
};

export const getProjectsTotalCountForWorkspace = async ({
  workspaceId,
  query = "",
  page = 1,
  limit = 5,
}: {
  workspaceId: string;
  query?: string;
  page?: number;
  limit?: number;
}) => {
  const zeroIndexedPage = page - 1;
  let supabaseQuery = supabaseAdminClient
    .from("projects")
    .select("id", {
      count: "exact",
      head: true,
    })
    .eq("workspace_id", workspaceId)
    .range(zeroIndexedPage * limit, (zeroIndexedPage + 1) * limit - 1);

  if (query) {
    supabaseQuery = supabaseQuery.ilike("name", `%${query}%`);
  }

  const { count, error } = await supabaseQuery.order("created_at", {
    ascending: false,
  });

  if (error) {
    throw error;
  }

  if (!count) {
    return 0;
  }

  return Math.ceil(count / limit) ?? 0;
};
