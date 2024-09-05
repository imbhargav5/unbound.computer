import { T } from '@/components/ui/Typography';
import { Button } from '@/components/ui/button';
import {
  HoverCard,
  HoverCardContent,
  HoverCardTrigger,
} from '@/components/ui/hover-card';
import { WorkspaceWithMembershipType } from '@/types';
import { getWorkspaceSubPath } from '@/utils/workspaces';
import { ArrowUpRight } from 'lucide-react';
import Link from 'next/link';
import { Card } from '../ui/card';

export async function SubscriptionCardSmall({
  workspace
}: {
  workspace: WorkspaceWithMembershipType
}) {
  const title = "Pro"
  const sidenote = "Manage your subscription"
  const description = "You're subscribed to the Pro plan. You can manage your subscription and billing details here."

  if (title) {
    return (
      <HoverCard>
        <HoverCardTrigger asChild>
          <Link href={getWorkspaceSubPath(workspace, `/settings/billing`)}>
            <div className="group cursor-pointer flex flex-col gap-1 items-start p-2 py-2 pb-3 border     w-full rounded-lg">
              <T.P className="font-semibold ">{title} Pro</T.P>
              {sidenote ? (
                <T.Small className=" font-normal  group-hover:underline underline-offset-4">
                  {sidenote}
                </T.Small>
              ) : null}
            </div>
          </Link>
        </HoverCardTrigger>
        <HoverCardContent className="w-60">{description}</HoverCardContent>
      </HoverCard>
    );
  }
  return (
    <Card className='p-6 bg-secondary flex flex-col gap-4'>
      <p>{description}</p>
      <Link
        className="w-full cursor-pointer flex mr-2 gap-2 items-center mt-1 rounded-lg"
        href={getWorkspaceSubPath(workspace, `/settings/billing`)}
      >
        <Button variant="default" className="w-full">
          <ArrowUpRight className="h-5 w-5 mr-2 " />
          {sidenote}
        </Button>
      </Link>
    </Card >
  );
}
