import { connection } from "next/server";
import { Suspense } from "react";
import { PageHeading } from "@/components/page-heading";
import { Pagination } from "@/components/pagination-ui";
import { Search } from "@/components/search-ui";
import { Skeleton } from "@/components/ui/skeleton";
import { getUsersTotalPagesAction } from "@/data/admin/user";
import { AppAdminCreateUserDialog } from "./app-admin-create-user-dialog";
import { appAdminUserFiltersSchema } from "./schema";
import { UserList } from "./users-list";

export const metadata = {
  title: "User List | Admin Panel | Nextbase",
};

async function UsersListContent(props: { searchParams: Promise<unknown> }) {
  await connection();
  const searchParams = await props.searchParams;
  const validatedSearchParams = appAdminUserFiltersSchema.parse(searchParams);
  const suspenseKey = JSON.stringify(validatedSearchParams);
  const totalPagesActionResult = await getUsersTotalPagesAction(
    validatedSearchParams
  );
  if (typeof totalPagesActionResult?.data !== "undefined") {
    const totalPages = totalPagesActionResult.data;
    return (
      <div className="max-w-[1296px] space-y-4">
        <PageHeading
          subTitle="View all users in your app. Perform actions such as creating new users, sending users login links, debug bugs your users face by logging in as them and more!"
          title="Users"
        />
        <div className="flex justify-between space-x-3">
          <Search placeholder="Search Users... " />
          <AppAdminCreateUserDialog />
        </div>
        <Suspense
          fallback={<Skeleton className="h-6 w-full" />}
          key={suspenseKey}
        >
          <UserList filters={validatedSearchParams} />
        </Suspense>
        <Pagination totalPages={totalPages} />
      </div>
    );
  }
  if (totalPagesActionResult?.serverError) {
    return <div>{totalPagesActionResult.serverError}</div>;
  }
  return <div>Failed to load total pages</div>;
}

export default async function AdminUsersListPage(props: {
  searchParams: Promise<unknown>;
}) {
  return (
    <Suspense>
      <UsersListContent searchParams={props.searchParams} />
    </Suspense>
  );
}
