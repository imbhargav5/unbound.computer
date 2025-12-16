"use server";

import { format } from "date-fns";
import { Link } from "@/components/intl-link";
import {
  Table as ShadcnTable,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { getPaginatedWorkspaceListAction } from "@/data/admin/workspaces";
import type { AppAdminWorkspacesFiltersSchema } from "./schema";

export async function WorkspaceList({
  filters,
}: {
  filters: AppAdminWorkspacesFiltersSchema;
}) {
  const workspacesActionResult = await getPaginatedWorkspaceListAction(filters);
  console.log("workspacesActionResult", workspacesActionResult);

  if (workspacesActionResult?.data) {
    const workspaces = workspacesActionResult.data;
    return (
      <div className="space-y-2">
        <ShadcnTable>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Slug</TableHead>
              <TableHead>Created At</TableHead>
              <TableHead>Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {workspaces.map((workspace) => (
              <TableRow key={workspace.id}>
                <TableCell>
                  <Link href={`/app-admin/workspaces/${workspace.id}`}>
                    {workspace.name ?? "-"}
                  </Link>
                </TableCell>
                <TableCell>{workspace.slug ?? "-"}</TableCell>
                <TableCell>
                  {format(new Date(workspace.created_at), "PPpp")}
                </TableCell>
                <TableCell>
                  <span className="flex items-center space-x-2">
                    {/* Add actions here if needed */}
                  </span>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </ShadcnTable>
      </div>
    );
  }
  if (workspacesActionResult?.serverError) {
    console.log("***************");
    console.log(workspacesActionResult.serverError);
    return <div>{workspacesActionResult.serverError}</div>;
  }
  console.error(workspacesActionResult);
  return <div>Failed to load workspaces</div>;
}
