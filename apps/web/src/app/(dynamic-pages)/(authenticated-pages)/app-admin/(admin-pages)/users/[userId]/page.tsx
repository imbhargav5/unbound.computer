import { Suspense } from "react";
import { z } from "zod";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Typography } from "@/components/ui/typography-ui";
import { getSlimWorkspacesOfUserAction } from "@/data/admin/workspaces";

const paramsSchema = z.object({
  userId: z.string(),
});

async function WorkspacesTable({ params }: { params: Promise<unknown> }) {
  const { userId } = paramsSchema.parse(await params);

  const workspacesActionResult = await getSlimWorkspacesOfUserAction({
    userId,
  });

  if (workspacesActionResult?.data) {
    const workspaces = workspacesActionResult.data;
    return (
      <div className="space-y-6">
        <Typography.H2>Workspaces</Typography.H2>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Workspace Name</TableHead>
              <TableHead>Slug</TableHead>
              <TableHead>Membership Type</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {workspaces.map((workspace) => (
              <TableRow key={workspace.id}>
                <TableCell>{workspace.name ?? "-"}</TableCell>
                <TableCell>{workspace.slug ?? "-"}</TableCell>
                <TableCell>{workspace.membershipType ?? "-"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    );
  }
  if (workspacesActionResult?.serverError) {
    console.log("***************");
    console.log(workspacesActionResult.serverError);
    return <div>{workspacesActionResult.serverError}</div>;
  }
  console.error(workspacesActionResult);
  return <div>Failed to load workspaces for user</div>;
}

export default async function AdminUserPage(props: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense fallback={<Skeleton className="h-6 w-full" />}>
      <WorkspacesTable params={props.params} />
    </Suspense>
  );
}
