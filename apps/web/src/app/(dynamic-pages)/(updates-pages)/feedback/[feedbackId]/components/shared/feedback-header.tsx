import type { DBTable } from "@/types";
import { FeedbackAvatarServer } from "../../feedback-avatar-server";

interface FeedbackHeaderProps {
  title: string;
  feedback: DBTable<"marketing_feedback_threads">;
}

export async function FeedbackHeader({ title, feedback }: FeedbackHeaderProps) {
  return (
    <>
      {/* Title */}
      <h1 className="mb-4 font-semibold text-foreground text-xl leading-snug">
        {title}
      </h1>

      {/* Author Info */}
      <div className="mb-6">
        <FeedbackAvatarServer feedback={feedback} />
      </div>
    </>
  );
}
