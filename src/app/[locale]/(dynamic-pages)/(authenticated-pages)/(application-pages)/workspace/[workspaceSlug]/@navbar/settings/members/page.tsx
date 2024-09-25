import { Link } from '@/components/intl-link';
import { getCachedWorkspaceBySlug } from '@/rsc-data/user/workspaces';
import { cn } from '@/utils/cn';
import { getWorkspaceSubPath } from '@/utils/workspaces';
import { workspaceSlugParamSchema } from '@/utils/zod-schemas/params';
import { ArrowLeftIcon } from '@radix-ui/react-icons';

export default async function WorkspaceSettingsMembersNavbar({
  params,
}: {
  params: unknown;
}) {
  const { workspaceSlug } = workspaceSlugParamSchema.parse(params);
  const workspace = await getCachedWorkspaceBySlug(workspaceSlug);

  return (
    <div className={cn('hidden', 'relative flex gap-2 items-center')}>
      <Link
        className="flex gap-1.5 py-1.5 px-3 cursor-pointer items-center group rounded-md transition hover:cursor-pointer hover:bg-primary-100 dark:hover:bg-primary-900"
        href={getWorkspaceSubPath(workspace, '/home')}
      >
        <ArrowLeftIcon className="w-4 h-4 text-primary-500 dark:text-primary-500 group-hover:text-primary-700 dark:group-hover:text-primary-700" />
        <span className="text-primary-500 dark:text-primary-500 group-hover:text-primary-700 dark:group-hover:text-primary-700 text-sm font-normal">
          Back to Organization
        </span>
      </Link>
    </div>
  );
}
