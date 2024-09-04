import { cn } from '@/lib/utils';
import { SlimWorkspaces } from '@/types';
import Image from 'next/image';
import Link from 'next/link';
import darkLogo from 'public/logos/nextbase-dark-logo.png';
import lightLogo from 'public/logos/nextbase-light-logo.png';
import { T } from '../ui/Typography';
import { WorkspaceSwitcher } from './OrganizationSwitcher';
import { SidebarClose } from './SidebarClose';
type Props = {
  workspaceId?: string;
  slimWorkspaces?: SlimWorkspaces;
};

export function SwitcherAndToggle({ workspaceId, slimWorkspaces }: Props) {
  return (
    <div className="flex items-center w-full gap-1 justify-between">
      {workspaceId && slimWorkspaces ? (
        <WorkspaceSwitcher
          currentWorkspaceId={workspaceId}
          slimWorkspaces={slimWorkspaces}
        />
      ) : <Link
        href="/dashboard"
        className="ml-2 cursor-pointer flex items-center gap-1 w-full"
      >
        <Image
          width={36}
          src={lightLogo}
          alt="Nextbase Logo"
          className={cn(
            'rotate-0 scale-100 transition-all dark:-rotate-90 dark:scale-0',
            '-ml-2 ',
          )}
        />
        <Image
          width={36}
          src={darkLogo}
          alt="Nextbase Logo"
          className={cn(
            ' absolute rotate-90 scale-0 transition-all dark:rotate-0 dark:scale-100',
            '-ml-2 ',
          )}
        />
        <T.P className="text-sm font-medium text-neutral-600 dark:text-slate-300">
          Nextbase
        </T.P>
      </Link>}
      <SidebarClose />
    </div>
  );
}
