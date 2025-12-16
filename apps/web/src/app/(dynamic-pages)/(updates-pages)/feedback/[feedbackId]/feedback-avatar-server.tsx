import { formatDistance } from "date-fns";
import { connection } from "next/server";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { anonGetUserProfile } from "@/data/user/elevated-queries";
import type { DBTable } from "@/types";

export async function FeedbackAvatarServer({
  feedback,
}: {
  feedback: DBTable<"marketing_feedback_threads">;
}) {
  await connection();
  const profile = await anonGetUserProfile(feedback.user_id);
  const timeAgo = formatDistance(new Date(feedback.created_at), new Date(), {
    addSuffix: true,
  });
  return (
    <div className="flex items-center gap-2.5">
      <Avatar className="h-7 w-7">
        <AvatarImage alt="User avatar" src={profile?.avatar_url ?? undefined} />
        <AvatarFallback className="bg-muted font-medium text-muted-foreground text-xs">
          {profile?.full_name?.charAt(0)}
        </AvatarFallback>
      </Avatar>
      <div className="flex items-center gap-1.5 text-sm">
        <span className="font-medium text-foreground">
          {profile?.full_name ?? "New User"}
        </span>
        <span className="text-muted-foreground">·</span>
        <span className="text-muted-foreground">{timeAgo}</span>
      </div>
    </div>
  );
}
