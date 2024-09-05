import { PageHeading } from '@/components/PageHeading';
import { getRoadmap } from '@/data/admin/internal-roadmap';
import { serverGetUserType } from '@/utils/server/serverGetUserType';
import { userRoles } from '@/utils/userTypes';
import { Suspense } from 'react';
import { AppAdminRoadmap } from './AppAdminRoadmap';
import { Roadmap } from './Roadmap';
import { Skeleton } from '@/components/ui/skeleton';

export default async function Page() {
  const roadmapData = await getRoadmap();
  const userRoleType = await serverGetUserType();
  return (
    <div className="space-y-10 max-w-[1296px]">
      <PageHeading
        title="Roadmap"
        titleClassName="text-2xl font-semibold tracking-normal"
        subTitle="This is where you see where the application is going"
      />

      {userRoleType === userRoles.ADMIN ? (
        <Suspense fallback={<Skeleton className="w-full h-6" />}>
          <AppAdminRoadmap roadmapData={roadmapData} />
        </Suspense>
      ) : (
        <Suspense fallback={<Skeleton className="w-full h-6" />}>
          <Roadmap roadmapData={roadmapData} />
        </Suspense>
      )}
    </div>
  );
}
