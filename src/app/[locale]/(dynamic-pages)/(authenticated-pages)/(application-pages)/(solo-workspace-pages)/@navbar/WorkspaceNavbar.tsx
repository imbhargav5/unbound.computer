// https://github.com/vercel/next.js/issues/58272
import { Link } from '@/components/intl-link';
import { T } from '@/components/ui/Typography';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { getCachedSoloWorkspace } from '@/rsc-data/user/workspaces';
import { WorkspaceWithMembershipType } from '@/types';
import { getWorkspaceSubPath } from '@/utils/workspaces';
import { UsersRound } from 'lucide-react';
import { notFound } from 'next/navigation';
import { Suspense } from 'react';

export async function generateMetadata() {
  try {
    const workspace = await getCachedSoloWorkspace();

    return {
      title: `${workspace.name} | Workspace | Nextbase Ultimate`,
      description: 'Workspace title',
    };
  } catch (error) {
    return {
      title: 'Not found',
    };
  }
}

async function Title({ workspace }: { workspace: WorkspaceWithMembershipType }) {
  return (
    <div className="flex items-center gap-2">
      <UsersRound className="w-4 h-4" />
      <T.P>{workspace.name}</T.P>
      <Badge variant="outline" className="lg:inline-flex hidden">
        Organization
      </Badge>
    </div>
  );
}

export async function WorkspaceNavbar() {
  try {
    const workspace = await getCachedSoloWorkspace();
    return (
      <div className="flex items-center">
        <Link href={getWorkspaceSubPath(workspace, '/home')}>
          <span className="flex items-center space-x-2">
            <Suspense fallback={<Skeleton className="w-16 h-6" />}>
              <Title workspace={workspace} />
            </Suspense>
          </span>
        </Link>
      </div>
    );
  } catch (error) {
    return notFound()
  }
}
