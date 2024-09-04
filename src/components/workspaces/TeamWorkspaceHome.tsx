import { WorkspacePageHeading } from './WorkspacePageHeading';

export async function TeamWorkspaceHome({ workspaceId, workspaceSlug }: { workspaceId: string; workspaceSlug: string }) {
    return (
        <div>
            <WorkspacePageHeading workspaceId={workspaceId} workspaceSlug={workspaceSlug} />
            {/* Add team workspace specific content here */}
        </div>
    );
}
