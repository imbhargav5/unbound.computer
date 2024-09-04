import { getWorkspaces } from '@/data/user/workspaces';
import Link from 'next/link';

export async function WorkspaceNavigation({ userId }: { userId: string }) {
    const workspaces = await getWorkspaces(userId);

    return (
        <nav>
            <ul>
                {workspaces.map((workspace) => (
                    <li key={workspace.id}>
                        <Link href={workspace.is_solo ? '/home' : `/workspace/${workspace.slug}/home`}>
                            {workspace.title}
                        </Link>
                    </li>
                ))}
            </ul>
        </nav>
    );
}
