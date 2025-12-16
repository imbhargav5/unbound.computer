import { clsx } from "clsx";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";

export function FeedbackDetailFallback() {
  return (
    <div className="flex h-full flex-col rounded-lg border py-2">
      <div className="p-6">
        <Skeleton className="h-[200px] w-full" />
      </div>
      <Separator orientation="horizontal" />
      <div className="flex-1 overflow-y-auto overflow-x-visible px-10 py-10 shadow-inner">
        <Skeleton className="h-[150px] w-full rounded-xl" />
      </div>
      <div className="border-t p-4">
        <div className="grid w-full gap-2">
          <Skeleton className="h-[80px] w-full" />
          <Skeleton className="h-[40px] w-full" />
        </div>
      </div>
    </div>
  );
}

function FeedbackPageFallbackUI({ feedbackId }: { feedbackId: string }) {
  return (
    <div className="flex h-full md:gap-2">
      <div
        className={clsx(
          feedbackId ? "hidden" : "",
          "h-full flex-1 flex-col md:flex"
        )}
      >
        <div className="mb-4 flex flex-col gap-2">
          <Skeleton className="h-[40px]" />
          <div className="flex gap-2">
            <Skeleton className="h-[32px] w-28" />
            <Skeleton className="h-[32px] w-28" />
            <Skeleton className="h-[32px] w-28" />
          </div>
        </div>
        <div className="mb-4 flex flex-1 flex-col gap-2 overflow-y-auto">
          <Skeleton className="h-[150px] w-full rounded-xl" />
          <Skeleton className="h-[150px] w-full rounded-xl" />
          <Skeleton className="h-[150px] w-full rounded-xl" />
        </div>
        <div className="border-t py-2">
          <div className="flex items-center justify-between">
            <Skeleton className="h-[40px] w-10" />
            <Skeleton className="h-[40px] w-10" />
            <Skeleton className="h-[40px] w-10" />
          </div>
        </div>
      </div>
      <Separator className="hidden md:block" orientation="vertical" />
      <div
        className={clsx(!feedbackId && "hidden", "relative flex-1 md:block")}
      >
        <FeedbackDetailFallback />
      </div>
    </div>
  );
}

export default FeedbackPageFallbackUI;
