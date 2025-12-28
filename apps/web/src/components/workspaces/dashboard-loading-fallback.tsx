import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export const DashboardLoadingFallback = () => (
  <div className="mt-8 flex w-full flex-col space-y-12">
    <div className="mb-6 flex items-center justify-between">
      <Skeleton className="h-10 w-48 border" />
      <div className="hidden gap-2 md:flex">
        <Skeleton className="h-10 w-48 border" />
        <Skeleton className="h-10 w-48 border" />
      </div>
    </div>
    <Card className="p-8">
      <Skeleton className="h-10 w-48" />
      <Skeleton className="mt-2 h-6 w-32" />
      <Skeleton className="mt-4 h-64 w-full" />
    </Card>
  </div>
);
