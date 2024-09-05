import { PageHeading } from '@/components/PageHeading';
import { Pagination } from '@/components/Pagination';
import { Search } from '@/components/Search';
import { Skeleton } from '@/components/ui/skeleton';
import { getWorkspacesTotalPages } from '@/data/admin/organizations';
import { Suspense } from 'react';
import { OrganizationList } from './OrganizationList';
import { appAdminOrganizationsFiltersSchema } from './schema';

export const metadata = {
  title: 'Organizations List | Admin Panel | Nextbase',
};

export default async function AdminOrganizationsList({
  searchParams,
}: {
  searchParams: unknown;
}) {
  const validatedSearchParams =
    appAdminOrganizationsFiltersSchema.parse(searchParams);
  const totalPages = await getWorkspacesTotalPages(validatedSearchParams);
  const suspenseKey = JSON.stringify(validatedSearchParams);

  return (
    <div className="space-y-4 max-w-[1296px]">
      <PageHeading
        title="Organizations"
        subTitle="View all organizations created by users in your app."
      ></PageHeading>
      <div className="flex justify-between space-x-3">
        <Search placeholder="Search Organizations... " />
        <div />
      </div>
      <Suspense key={suspenseKey} fallback={<Skeleton className="w-full h-6" />}>
        <OrganizationList filters={validatedSearchParams} />
        <div />
      </Suspense>
      <Pagination totalPages={totalPages} />
    </div>
  );
}
