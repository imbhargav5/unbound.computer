import { Suspense } from "react";
import { PageHeading } from "@/components/page-heading";
import { Pagination } from "@/components/pagination-ui";
import { Search } from "@/components/search-ui";
import { Skeleton } from "@/components/ui/skeleton";
import { getWorkspacesTotalPagesAction } from "@/data/admin/workspaces";
import { appAdminWorkspacesFiltersSchema } from "./schema";
import { WorkspaceList } from "./workspace-list";

export const metadata = {
  title: "Workspaces List | Admin Panel | Nextbase",
};

async function WorkspacesListContent(props: {
  searchParams: Promise<unknown>;
}) {
  const searchParams = await props.searchParams;
  const validatedSearchParams =
    appAdminWorkspacesFiltersSchema.parse(searchParams);
  const suspenseKey = JSON.stringify(validatedSearchParams);
  const totalPagesActionResult = await getWorkspacesTotalPagesAction(
    validatedSearchParams
  );

  if (typeof totalPagesActionResult?.data !== "undefined") {
    const totalPages = totalPagesActionResult.data;
    return (
      <div className="max-w-[1296px] space-y-4">
        <PageHeading
          subTitle="View all workspaces created by users in your app."
          title="Workspaces"
        />
        <div className="flex justify-between space-x-3">
          <Search placeholder="Search Workspaces... " />
          <div />
        </div>
        <Suspense
          fallback={<Skeleton className="h-6 w-full" />}
          key={suspenseKey}
        >
          <WorkspaceList filters={validatedSearchParams} />
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

export default async function AdminWorkspacesList(props: {
  searchParams: Promise<unknown>;
}) {
  return (
    <Suspense>
      <WorkspacesListContent searchParams={props.searchParams} />
    </Suspense>
  );
}
