import { Skeleton } from "@/components/ui/skeleton";

export default function Loading() {
  return <div className="flex flex-col space-y-6">
    <div className="flex justify-between items-start">
      <Skeleton className="h-6 w-24" />
      <Skeleton className="flex space-x-4">
        <Skeleton className="h-10 w-full" />
      </Skeleton>
    </div>
    <div className="space-y-4">
      <Skeleton className="h-44 w-full" />
      <Skeleton className="h-24 w-full" />
    </div>
    <div className="space-y-3">
      <Skeleton className="h-6 w-32" />
      <div className="flex space-x-4 gap-2">
        <Skeleton className="h-24 w-full" />
        <div className="flex gap-4 w-full">
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
        </div>
      </div>

    </div>
  </div>
}
