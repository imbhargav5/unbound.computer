import { Link } from '@/components/intl-link';
import { RecentPublicFeedback } from '@/components/RecentPublicFeedback';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { ArrowLeft, Info } from 'lucide-react';
import { Suspense } from 'react';

function RecentFeedbackSkeleton() {
  return (
    <div className="space-y-2">
      <Skeleton className="h-4 w-full" />
      <Skeleton className="h-4 w-full" />
      <Skeleton className="h-4 w-full" />
    </div>
  );
}

export default function FeedbackDetailLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="h-full flex flex-col">
      <div className="p-2">
        <Button variant="ghost" asChild className="mb-4">
          <Link href="/feedback">
            <ArrowLeft className="mr-2 h-4 w-4" />
            Back to all feedback
          </Link>
        </Button>
      </div>
      <div className="flex flex-grow">
        <div className="flex-grow border rounded-md pt-4">{children}</div>
        <aside className="w-64 ml-4 p-4 border rounded-md bg-secondary flex-shrink-0 space-y-6">
          <div>
            <div className="flex items-center mb-2 text-primary">
              <Info className="mr-2 h-5 w-5" />
              <h3 className="font-semibold">Community Guidelines</h3>
            </div>
            <p className="text-sm text-muted-foreground">
              Please remember that this is a public forum. We kindly ask all
              users to conduct themselves in a civil and respectful manner.
              Let&apos;s foster a positive environment for everyone.
            </p>
          </div>
          <div>
            <h3 className="font-semibold text-primary mb-2">Recent Feedback</h3>
            <Suspense fallback={<RecentFeedbackSkeleton />}>
              <RecentPublicFeedback />
            </Suspense>
          </div>
        </aside>
      </div>
    </div>
  );
}
