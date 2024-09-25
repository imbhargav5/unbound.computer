import { Link } from '@/components/intl-link';
import { T } from '@/components/ui/Typography';
import { getCachedWorkspaceBySlug } from '@/rsc-data/user/workspaces';
import { cn } from '@/utils/cn';
import { getWorkspaceSubPath } from '@/utils/workspaces';
import { workspaceSlugParamSchema } from '@/utils/zod-schemas/params';
import { ArrowLeftIcon } from '@radix-ui/react-icons';

export default async function WorkspaceSettingsNavbar({
  params,
}: {
  params: unknown;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);
  return (
    <div className={cn('hidden lg:block', 'relative ')}>
      <T.P className="my-0">
        <Link href={getWorkspaceSubPath(workspace, '/home')}>
          <span className="space-x-2 flex items-center">
            <ArrowLeftIcon />
            <span>Back to Organization</span>
          </span>
        </Link>
      </T.P>
    </div>
  );
}
