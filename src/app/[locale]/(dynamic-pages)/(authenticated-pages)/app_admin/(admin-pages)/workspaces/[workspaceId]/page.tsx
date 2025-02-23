import { Typography } from "@/components/ui/Typography";

export default async function AdminWorkspacePage({
  params,
}: {
  params: { workspaceId: string };
}) {
  return (
    <div className="space-y-2">
      <Typography.H1 className="md:text-xl lg:text-2xl font-bold">
        Workspace Details
      </Typography.H1>
      <Typography.P>
        View and manage the details of the workspace with ID:{" "}
        <span className="font-bold">{params.workspaceId}</span>
      </Typography.P>
      <Typography.Subtle>Coming soon!</Typography.Subtle>
    </div>
  );
}
