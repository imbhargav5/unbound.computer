import { cn } from "@/utils/cn";

interface FeedbackCardProps {
  children: React.ReactNode;
  className?: string;
}

export function FeedbackCard({ children, className }: FeedbackCardProps) {
  return (
    <div className={cn("rounded-lg border bg-card p-6", className)}>
      {children}
    </div>
  );
}
