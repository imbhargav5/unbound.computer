"use client";

import { useQuery } from "@tanstack/react-query";
import { useEffect } from "react";
import { getProjectCommentsClient } from "@/data/user/client/projects";
import { getQueryClient } from "@/lib/query-client";
import { supabaseUserClientComponent } from "@/supabase-clients/user/supabase-user-client-component";
import type { CommentWithUser } from "@/types";

/**
 * Custom hook to fetch and subscribe to realtime project comments
 * @param projectId - The ID of the project whose comments to fetch and subscribe to
 * @returns Object containing comments data and loading state
 */
export function useRealtimeComments(projectId: string) {
  const queryClient = getQueryClient();
  const {
    data: comments = [],
    isLoading,
    refetch,
  } = useQuery<CommentWithUser[]>(
    {
      queryKey: ["projectComments", projectId],
      queryFn: () => getProjectCommentsClient(projectId),
      initialData: [],
      staleTime: 0,
    },
    queryClient
  );

  // Set up realtime subscription
  useEffect(() => {
    const channelId = `project-comments:${projectId}`;
    const channel = supabaseUserClientComponent
      .channel(channelId)
      .on(
        "postgres_changes",
        {
          event: "*", // Listen to all events (INSERT, UPDATE, DELETE)
          schema: "public",
          table: "project_comments",
          filter: `project_id=eq.${projectId}`,
        },
        () => {
          queryClient.invalidateQueries({
            queryKey: ["projectComments", projectId],
          });
        }
      )
      .subscribe();

    return () => {
      supabaseUserClientComponent.removeChannel(channel);
    };
  }, [projectId, refetch, queryClient]);

  return {
    comments,
    isLoading,
  };
}
