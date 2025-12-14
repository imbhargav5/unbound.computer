import { formatDistance } from "date-fns";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { anonGetUserProfile } from "@/data/user/elevated-queries";
import type { DBTable } from "@/types";

export async function CommentCard({
  comment,
}: {
  comment: DBTable<"marketing_feedback_comments">;
}) {
  const userProfile = await anonGetUserProfile(comment.user_id);

  return (
    <div
      className="flex gap-3"
      data-comment-id={comment.id}
      data-testid={`comment-timeline-item-${comment.id}`}
    >
      <Avatar className="h-8 w-8 shrink-0">
        <AvatarImage
          alt={userProfile?.full_name ?? "User"}
          src={userProfile?.avatar_url ?? undefined}
        />
        <AvatarFallback className="bg-muted font-medium text-muted-foreground text-xs">
          {userProfile?.full_name?.charAt(0) ?? "U"}
        </AvatarFallback>
      </Avatar>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="font-medium text-foreground text-sm">
            {userProfile?.full_name ?? "User"}
          </span>
          <span className="text-muted-foreground text-xs">
            {formatDistance(new Date(comment.created_at), new Date(), {
              addSuffix: true,
            })}
          </span>
        </div>
        <p className="mt-1 text-muted-foreground text-sm leading-relaxed">
          {comment.content}
        </p>
      </div>
    </div>
  );
}
