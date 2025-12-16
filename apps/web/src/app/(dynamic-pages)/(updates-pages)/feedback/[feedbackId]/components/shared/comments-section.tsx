import { FeedbackCard } from "./feedback-card";

interface CommentsSectionProps {
  children: React.ReactNode;
}

export function CommentsSection({ children }: CommentsSectionProps) {
  return <FeedbackCard>{children}</FeedbackCard>;
}
