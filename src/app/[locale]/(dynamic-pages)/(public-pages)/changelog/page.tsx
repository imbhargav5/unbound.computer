import { PageHeading } from '@/components/PageHeading';
import { Button } from '@/components/ui/button';
import { anonGetAllChangelogItems } from '@/data/anon/internalChangelog';
import { serverGetUserType } from '@/utils/server/serverGetUserType';
import { userRoles } from '@/utils/userTypes';
import { Plus } from 'lucide-react';
import Link from 'next/link';
import { Suspense } from 'react';
import { ChangelogPosts } from './AppAdminChangelog';
import { ChangelogListSkeletonFallBack } from './_components/ChangelogSkeletonFallBack';

export default async function Page() {
  const userRoleType = await serverGetUserType();
  const changelogs = await anonGetAllChangelogItems();
  return (
    <div className="space-y-10 max-w-[1296px] py-8">
      <div className="flex w-full justify-between items-center">
        <PageHeading
          title="Changelog List"
          titleClassName="text-2xl font-semibold tracking-normal"
          subTitle="This is the changelog for the application. It will be updated as new
              features are added and bugs are fixed."
        />
        {userRoleType === userRoles.ADMIN && (
          <Button asChild name="create-changelog-button">
            <Link href="/app_admin/changelog">
              <Plus className="mr-2 size-4" />
              Create Changelog
            </Link>
          </Button>
        )}
      </div>
      <Suspense fallback={<ChangelogListSkeletonFallBack />}>
        <ChangelogPosts changelogs={changelogs} />
      </Suspense>
    </div>
  );
}
