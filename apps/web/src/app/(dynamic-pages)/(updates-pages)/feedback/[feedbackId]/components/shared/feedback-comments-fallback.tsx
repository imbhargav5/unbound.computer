import { Skeleton } from "@/components/ui/skeleton";

export function FeedbackCommentsFallback() {
  return (
    <div className="space-y-5">
      {[1, 2, 3].map((i) => (
        <div className="flex gap-3" key={i}>
          <Skeleton className="h-8 w-8 shrink-0 rounded-full" />
          <div className="flex-1">
            <div className="flex items-center gap-2">
              <Skeleton className="h-4 w-24" />
              <Skeleton className="h-3 w-16" />
            </div>
            <Skeleton className="mt-2 h-12 w-full" />
          </div>
        </div>
      ))}
    </div>
  );
}
