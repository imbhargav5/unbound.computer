"use server";
import { refresh } from "next/cache";
import { z } from "zod";
import { redirect } from "@/i18n/navigation";
import { authActionClient } from "@/lib/safe-action";
import { supabaseAdminClient } from "@/supabase-clients/admin/supabase-admin-client";
import { createSupabaseUserServerActionClient } from "@/supabase-clients/user/create-supabase-user-server-action-client";
import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/create-supabase-user-server-component-client";
import type { CommentWithUser } from "@/types";
import { normalizeComment } from "@/utils/comments";
import { serverGetRefererLocale } from "@/utils/server/server-get-referer-locale";

export async function getSlimProjectById(projectId: string) {
  const supabaseClient = await createSupabaseUserServerComponentClient();
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

export const getSlimProjectBySlug = async (projectSlug: string) => {
  const supabaseClient = await createSupabaseUserServerComponentClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .select("id, slug, name")
    .eq("slug", projectSlug)
    .single();
  if (error) {
    console.log("getslimprojectbyslug", error);
    throw error;
  }
  return data;
};

export async function getProjectById(projectId: string) {
  const supabaseClient = await createSupabaseUserServerComponentClient();
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

export async function getProjectBySlug(projectSlug: string) {
  const supabaseClient = await createSupabaseUserServerComponentClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .select("*")
    .eq("slug", projectSlug)
    .single();
  if (error) {
    console.log("getprojectbyslug", error, projectSlug);
    throw error;
  }
  return data;
}

export async function getProjectTitleById(projectId: string) {
  const supabaseClient = await createSupabaseUserServerComponentClient();
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

export const getProjectComments = async (
  projectId: string
): Promise<Array<CommentWithUser>> => {
  const supabase = await createSupabaseUserServerComponentClient();
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
const createProjectCommentSchema = z.object({
  projectId: z.string(),
  projectSlug: z.string(),
  text: z.string(),
});

export const createProjectCommentAction = authActionClient
  .inputSchema(createProjectCommentSchema)
  .action(
    async ({
      parsedInput: { projectId, projectSlug, text },
      ctx: { userId },
    }) => {
      const supabaseClient = await createSupabaseUserServerActionClient();

      const { data, error } = await supabaseClient
        .from("project_comments")
        .insert({ project_id: projectId, text, user_id: userId })
        .select("*, user_profiles(*)")
        .single();

      if (error) {
        throw new Error(error.message);
      }

      return {
        comment: normalizeComment(data),
      };
    }
  );

const approveProjectSchema = z.object({
  projectId: z.uuid(),
  projectSlug: z.string(),
});

export const approveProjectAction = authActionClient
  .inputSchema(approveProjectSchema)
  .action(async ({ parsedInput: { projectId, projectSlug } }) => {
    const supabaseClient = await createSupabaseUserServerActionClient();

    const { data, error } = await supabaseClient
      .from("projects")
      .update({ project_status: "approved" })
      .eq("id", projectId)
      .select("*")
      .single();

    if (error) {
      throw new Error(error.message);
    }

    return data;
  });

const rejectProjectSchema = z.object({
  projectId: z.uuid(),
  projectSlug: z.string(),
});

export const rejectProjectAction = authActionClient
  .inputSchema(rejectProjectSchema)
  .action(async ({ parsedInput: { projectId, projectSlug } }) => {
    const supabaseClient = await createSupabaseUserServerActionClient();

    const { data, error } = await supabaseClient
      .from("projects")
      .update({ project_status: "draft" })
      .eq("id", projectId)
      .select("*")
      .single();

    if (error) {
      throw new Error(error.message);
    }

    return data;
  });
const submitProjectForApprovalSchema = z.object({
  projectId: z.uuid(),
  projectSlug: z.string(),
});

export const submitProjectForApprovalAction = authActionClient
  .inputSchema(submitProjectForApprovalSchema)
  .action(async ({ parsedInput: { projectId, projectSlug } }) => {
    const supabaseClient = await createSupabaseUserServerActionClient();

    const { data, error } = await supabaseClient
      .from("projects")
      .update({ project_status: "pending_approval" })
      .eq("id", projectId)
      .select("*")
      .single();

    if (error) {
      throw new Error(error.message);
    }

    return data;
  });

const markProjectAsCompletedSchema = z.object({
  projectId: z.uuid(),
  projectSlug: z.string(),
});

export const markProjectAsCompletedAction = authActionClient
  .inputSchema(markProjectAsCompletedSchema)
  .action(async ({ parsedInput: { projectId, projectSlug } }) => {
    const supabaseClient = await createSupabaseUserServerActionClient();

    const { data, error } = await supabaseClient
      .from("projects")
      .update({ project_status: "completed" })
      .eq("id", projectId)
      .select("*")
      .single();

    if (error) {
      throw new Error(error.message);
    }
    refresh();
    return data;
  });
export const getProjects = async ({
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
  const supabase = await createSupabaseUserServerComponentClient();
  let supabaseQuery = supabase
    .from("projects")
    .select("*")
    .eq("workspace_id", workspaceId)
    .range(zeroIndexedPage * limit, (zeroIndexedPage + 1) * limit - 1)
    .order("created_at", { ascending: false });

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

export async function getSlimProjectByIdForWorkspace(projectId: string) {
  const supabaseClient = await createSupabaseUserServerComponentClient();
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
  const supabaseClient = await createSupabaseUserServerComponentClient();
  const { data, error } = await supabaseClient
    .from("projects")
    .select("id, slug, name")
    .eq("slug", projectSlug)
    .single();
  if (error) {
    throw error;
  }
  return data;
};

const createProjectSchema = z.object({
  workspaceId: z.uuid(),
  name: z.string(),
  slug: z.string(),
});

export const createProjectAction = authActionClient
  .inputSchema(createProjectSchema)
  .action(async ({ parsedInput: { workspaceId, name, slug } }) => {
    const supabaseClient = await createSupabaseUserServerActionClient();

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
      throw new Error(error.message);
    }
    const locale = await serverGetRefererLocale();
    redirect({ href: `/project/${project.slug}`, locale });
    return project;
  });

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
  const supabase = await createSupabaseUserServerComponentClient();
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

const deleteProjectsSchema = z.object({
  projectIds: z.array(z.string()),
});

export const deleteProjectsAction = authActionClient
  .inputSchema(deleteProjectsSchema)
  .action(async ({ parsedInput: { projectIds } }) => {
    const supabase = await createSupabaseUserServerActionClient();

    const { error } = await supabase
      .from("projects")
      .delete()
      .in("id", projectIds);

    if (error) {
      throw new Error(error.message);
    }

    return { success: true };
  });

const updateProjectSchema = z.object({
  projectId: z.string(),
  name: z.string().min(1, "Project name is required"),
  project_status: z.enum([
    "draft",
    "pending_approval",
    "approved",
    "completed",
  ]),
});

export const updateProjectAction = authActionClient
  .inputSchema(updateProjectSchema)
  .action(async ({ parsedInput: { projectId, name, project_status } }) => {
    const supabase = await createSupabaseUserServerActionClient();

    const { error } = await supabase
      .from("projects")
      .update({
        name,
        project_status,
        updated_at: new Date().toISOString(),
      })
      .eq("id", projectId);

    if (error) {
      throw new Error(error.message);
    }

    return { success: true };
  });
