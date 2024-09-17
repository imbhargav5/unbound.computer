import { PageHeading } from '@/components/PageHeading';
import { getWorkspaceName } from '@/data/user/workspaces';

export async function WorkspacePageHeading({
    workspaceId,
    workspaceSlug,
}: {
    workspaceId: string;
    workspaceSlug: string;
}) {
    const workspaceTitle = await getWorkspaceName(workspaceId);
    return (
        <PageHeading
            title={workspaceTitle}
            titleHref={`/${workspaceSlug}`}
        />
    );
}
