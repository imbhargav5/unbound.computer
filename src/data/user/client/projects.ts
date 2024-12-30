import type { Tables } from "@/lib/database.types";
import { supabaseUserClientComponent } from "@/supabase-clients/user/supabaseUserClientComponent";
import type { ProjectsFilterSchema } from "@/utils/zod-schemas/projects";

export async function getProjectsClient({
  workspaceId,
  filters,
}: {
  workspaceId: string;
  filters: ProjectsFilterSchema;
}) {
  const { query, sorting } = filters;

  let supabaseQuery = supabaseUserClientComponent
    .from("projects")
    .select("*", { count: "exact" })
    .eq("workspace_id", workspaceId);

  if (query) {
    supabaseQuery = supabaseQuery.ilike("name", `%${query}%`);
  }

  if (sorting && sorting.length > 0) {
    const { id, desc } = sorting[0] as { id: string; desc: boolean };
    if (id === "name" || id === "project_status") {
      supabaseQuery = supabaseQuery.order(id, { ascending: !desc });
    }
  } else {
    supabaseQuery = supabaseQuery.order("created_at", { ascending: false });
  }

  const { data, error, count } = await supabaseQuery;

  if (error) {
    throw error;
  }

  return {
    data: data as Tables<"projects">[],
    count: count ?? 0,
  };
}
