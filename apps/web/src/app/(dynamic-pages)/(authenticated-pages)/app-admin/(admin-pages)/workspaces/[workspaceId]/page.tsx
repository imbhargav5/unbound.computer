import { Suspense } from "react";
import { Typography } from "@/components/ui/typography-ui";

async function AdminWorkspacePageContent(props: {
  params: Promise<{ workspaceId: string }>;
}) {
  const { workspaceId } = await props.params;
  return (
    <div className="space-y-2">
      <Typography.H1 className="font-bold md:text-xl lg:text-2xl">
        Workspace Details
      </Typography.H1>
      <Typography.P>
        View and manage the details of the workspace with ID:{" "}
        <span className="font-bold">{workspaceId}</span>
      </Typography.P>
      <Typography.Subtle>Coming soon!</Typography.Subtle>
    </div>
  );
}

export default async function AdminWorkspacePage(props: {
  params: Promise<{ workspaceId: string }>;
}) {
  return (
    <Suspense>
      <AdminWorkspacePageContent {...props} />
    </Suspense>
  );
}
