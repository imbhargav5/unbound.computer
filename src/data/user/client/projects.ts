import type { Tables } from "@/lib/database.types";
import { supabaseUserClientComponent } from "@/supabase-clients/user/supabaseUserClientComponent";
import type { SortingState } from "@tanstack/react-table";

export async function getProjectsClient({
  workspaceId,
  query = "",
  sorting,
}: {
  workspaceId: string;
  query?: string;
  sorting?: SortingState;
}) {
  let supabaseQuery = supabaseUserClientComponent
    .from("projects")
    .select("*")
    .eq("workspace_id", workspaceId);

  if (query) {
    supabaseQuery = supabaseQuery.ilike("name", `%${query}%`);
  }

  if (sorting && sorting.length > 0) {
    const { id, desc } = sorting[0];
    if (id === "name" || id === "project_status") {
      supabaseQuery = supabaseQuery.order(id, { ascending: !desc });
    }
  } else {
    supabaseQuery = supabaseQuery.order("created_at", { ascending: false });
  }

  const { data, error } = await supabaseQuery;

  if (error) {
    throw error;
  }

  return data as Tables<"projects">[];
}
