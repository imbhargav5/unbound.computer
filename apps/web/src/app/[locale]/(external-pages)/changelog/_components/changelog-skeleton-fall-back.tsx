import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";

export function ChangelogListSkeletonFallBack() {
  return (
    <div className="mx-auto w-full max-w-4xl">
      <h1 className="font-bold text-4xl">Changelog List</h1>
      <p className="mt-2 text-lg text-muted-foreground">
        This is the changelog for the application. It will be updated as new
        features are added and bugs are fixed.
      </p>
      <div className="mt-6 space-y-6">
        <div className="space-y-4 rounded-md border p-4">
          <div className="flex items-center justify-between">
            <Skeleton className="h-6 w-24" />
            <Skeleton className="h-6 w-16" />
            <Badge variant="secondary">NEW</Badge>
          </div>
          <Skeleton className="h-64 rounded-md" />
        </div>
        <div className="space-y-4 rounded-md border p-4">
          <div className="flex items-center justify-between">
            <Skeleton className="h-6 w-24" />
            <Skeleton className="h-6 w-16" />
          </div>
          <Skeleton className="h-64 rounded-md" />
        </div>
      </div>
    </div>
  );
}
