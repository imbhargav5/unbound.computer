import { PageHeading } from '@/components/PageHeading';
import { Pagination } from '@/components/Pagination';
import { Search } from '@/components/Search';
import { Skeleton } from '@/components/ui/skeleton';
import { getUsersTotalPages } from '@/data/admin/user';
import { Suspense } from 'react';
import { AppAdminCreateUserDialog } from './AppAdminCreateUserDialog';
import { UserList } from './UsersList';
import { appAdminUserFiltersSchema } from './schema';

export const metadata = {
  title: 'User List | Admin Panel | Nextbase',
};

export default async function AdminUsersListPage({
  searchParams,
}: {
  searchParams: unknown;
}) {
  const validatedSearchParams = appAdminUserFiltersSchema.parse(searchParams);
  const suspenseKey = JSON.stringify(validatedSearchParams);
  const totalPages = await getUsersTotalPages(validatedSearchParams);
  return (
    <div className="space-y-4 max-w-[1296px]">
      <PageHeading
        title="Users"
        subTitle="View all users in your app. Perform actions such as creating new users, sending users login links, debug bugs your users face by logging in as them and more!"
      ></PageHeading>
      <div className="flex justify-between space-x-3">
        <Search placeholder="Search Users... " />
        <AppAdminCreateUserDialog />
      </div>
      <Suspense key={suspenseKey} fallback={<Skeleton className="w-full h-6" />}>
        <UserList filters={validatedSearchParams} />
      </Suspense>
      <Pagination totalPages={totalPages} />
    </div>
  );
}
