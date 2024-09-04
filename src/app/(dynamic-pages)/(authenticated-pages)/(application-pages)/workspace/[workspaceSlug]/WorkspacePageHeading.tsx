import { PageHeading } from '@/components/PageHeading';
import { getWorkspaceTitle } from '@/data/user/workspaces';

export async function WorkspacePageHeading({
    workspaceId,
    workspaceSlug,
}: {
    workspaceId: string;
    workspaceSlug: string;
}) {
    const workspaceTitle = await getWorkspaceTitle(workspaceId);
    return (
        <PageHeading
            title={workspaceTitle}
            titleHref={`/${workspaceSlug}`}
        />
    );
}
