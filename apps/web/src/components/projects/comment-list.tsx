import { format } from "date-fns";
import { Suspense } from "react";
import { T } from "@/components/ui/typography-ui";
import { FallbackImage, UserAvatar } from "@/components/user-avatar";
import { UserFullName } from "@/components/user-full-name";
import type { CommentWithUser } from "@/types";

export function CommentList({ comments }: { comments: CommentWithUser[] }) {
  return comments.map((comment) => (
    <div
      className="grid grid-cols-[24px_1fr] items-start gap-3 px-6 py-4"
      key={comment.id}
    >
      <Suspense fallback={<FallbackImage size={24} />}>
        <UserAvatar size={24} userId={comment.user_id} />
      </Suspense>
      <div className="space-y-2">
        <Suspense>
          <UserFullName userId={comment.user_id} />
        </Suspense>
        <T.Small className="m-0">{comment.text}</T.Small>
        {comment.created_at ? (
          <T.Subtle className="text-muted-foreground text-xs">
            {format(new Date(comment.created_at), "PPpp")}
          </T.Subtle>
        ) : null}
      </div>
    </div>
  ));
}
