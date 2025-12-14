"use client";
import { CommentList } from "@/components/projects/comment-list";
import { useRealtimeComments } from "@/hooks/use-realtime-comments";

export function ProjectComments({ projectId }: { projectId: string }) {
  const { comments, isLoading } = useRealtimeComments(projectId);
  if (isLoading) return <div>Loading...</div>;
  return (
    <div className="grid-auto-rows-min grid divide-y">
      <CommentList comments={comments} />
    </div>
  );
}
