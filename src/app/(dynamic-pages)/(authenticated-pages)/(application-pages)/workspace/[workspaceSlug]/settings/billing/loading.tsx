import { Card } from '@/components/ui/card';
import { Skeleton } from '@/components/ui/skeleton';

export default function SubscriptionCardsFallback() {
  return (
    <div className="mt-6 grid grid-cols-1 gap-5 md:grid-cols-3">
      <Card className="overflow-hidden shadow w-full p-5">
        <div>
          <Skeleton className="h-6 w-3/4 mb-4" />
          <Skeleton className="h-4 w-1/4 mb-2" />
          <div className="space-y-2">
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-full" />
          </div>
          <div className="mt-6">
            <Skeleton className="h-10 w-full" />
          </div>
          <div className="mt-4">
            <Skeleton className="h-10 w-full" />
          </div>
        </div>
      </Card>
      <Card className="overflow-hidden shadow w-full p-5">
        <div>
          <Skeleton className="h-6 w-3/4 mb-4" />
          <Skeleton className="h-4 w-1/4 mb-2" />
          <div className="space-y-2">
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-full" />
          </div>
          <div className="mt-6">
            <Skeleton className="h-10 w-full" />
          </div>
          <div className="mt-4">
            <Skeleton className="h-10 w-full" />
          </div>
        </div>
      </Card>
      <Card className="overflow-hidden shadow w-full p-5">
        <div>
          <Skeleton className="h-6 w-3/4 mb-4" />
          <Skeleton className="h-4 w-1/4 mb-2" />
          <div className="space-y-2">
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-full" />
            <Skeleton className="h-4 w-full" />
          </div>
          <div className="mt-6">
            <Skeleton className="h-10 w-full" />
          </div>
          <div className="mt-4">
            <Skeleton className="h-10 w-full" />
          </div>
        </div>
      </Card>
    </div>
  );
}
