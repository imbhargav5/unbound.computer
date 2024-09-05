// https://github.com/vercel/next.js/issues/58272
import { T } from '@/components/ui/Typography';
import { Badge } from '@/components/ui/badge';
import { Skeleton } from '@/components/ui/skeleton';
import { getWorkspaceBySlug } from '@/data/user/workspaces';
import { WorkspaceWithMembershipType } from '@/types';
import { getWorkspaceSubPath } from '@/utils/workspaces';
import { workspaceSlugParamSchema } from '@/utils/zod-schemas/params';
import { UsersRound } from 'lucide-react';
import Link from 'next/link';
import { Suspense } from 'react';

export async function generateMetadata({ params }: { params: unknown }) {
  try {
    const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
    const workspace = await getWorkspaceBySlug(workspaceSlug)

    return {
      title: `${workspace.name} | Workspace | Nextbase Ultimate`,
      description: 'Organization title',
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

export default async function OrganizationNavbar({
  params,
}: {
  params: unknown;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getWorkspaceBySlug(workspaceSlug)
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
}
