import { Skeleton } from "@/components/ui/skeleton";

export const SettingsFormSkeleton = () => (
  <div className="max-w-md space-y-6 rounded-md p-6">
    <div className="space-y-3">
      <div className="font-semibold text-lg">
        <Skeleton className="h-6 w-48" />
      </div>
      <div className="text-sm">
        <Skeleton className="h-4 w-64" />
      </div>
      <Skeleton className="h-10 w-full" />
    </div>
    <div className="space-y-3">
      <div className="font-semibold text-lg">
        <Skeleton className="h-6 w-48" />
      </div>
      <div className="text-sm">
        <Skeleton className="h-4 w-64" />
      </div>
      <Skeleton className="h-10 w-full" />
    </div>
    <div className="pt-4">
      <Skeleton className="h-10 w-32" />
    </div>
  </div>
);
