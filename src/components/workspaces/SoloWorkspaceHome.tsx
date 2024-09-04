import { WorkspacePageHeading } from './WorkspacePageHeading';

export async function SoloWorkspaceHome({ workspaceId, workspaceSlug }: { workspaceId: string; workspaceSlug: string }) {
    return (
        <div>
            <WorkspacePageHeading workspaceId={workspaceId} workspaceSlug={workspaceSlug} />
            {/* Add solo workspace specific content here */}
        </div>
    );
}
