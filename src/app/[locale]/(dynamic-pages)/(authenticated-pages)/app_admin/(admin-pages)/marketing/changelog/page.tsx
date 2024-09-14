import { Button } from '@/components/Button';
import { CreateChangelogForm } from '@/components/changelog/CreateChangelogForm';
import { RecentlyFeedbackCard } from '@/components/changelog/RecentlyFeedbackCard';
import { getAllInternalFeedback } from '@/data/user/internalFeedback';
import { serverGetUserType } from '@/utils/server/serverGetUserType';
import { userRoles } from '@/utils/userTypes';
import { MessagesSquare } from 'lucide-react';
import Link from 'next/link';
import { redirect } from 'next/navigation';

export default async function Page() {
  const userRoleType = await serverGetUserType();
  const recentlyCompletedFeedbacks = await getAllInternalFeedback({
    statuses: ['completed'],
    types: ['bug', 'feature_request', 'general'],
    priorities: ['low', 'medium', 'high'],
    query: '',
  });

  if (userRoleType !== userRoles.ADMIN) {
    redirect('/changelog');
  }

  return (
    <div className="grid lg:grid-cols-6 lg:gap-8">
      <CreateChangelogForm />

      {recentlyCompletedFeedbacks.length > 0 && (
        <div className="mt-10 col-span-2 grid grid-cols-1 gap-4">
          <div>
            <h2 className="text-lg font-bold">Recently completed feedback</h2>
            <div className="flex flex-col gap-2 mt-2">
              {recentlyCompletedFeedbacks.slice(0, 3).map((feedback) => (
                <RecentlyFeedbackCard key={feedback.id} feedback={feedback} />
              ))}
            </div>
            <Button variant={'secondary'} asChild className="w-full mt-2">
              <Link
                href="/feedback?statuses=completed&page=1"
                target="_blank"
                className="flex gap-2"
              >
                <MessagesSquare className="size-4" /> View all completed
                feedback
              </Link>
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
