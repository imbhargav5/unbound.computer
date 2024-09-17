'use server';
import {
  Table as ShadcnTable,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { getPaginatedWorkspaceListAction } from '@/data/admin/workspaces';
import { format } from 'date-fns';
import { AppAdminWorkspacesFiltersSchema } from './schema';

export async function WorkspaceList({
  filters,
}: {
  filters: AppAdminWorkspacesFiltersSchema;
}) {
  const workspaces = await getPaginatedWorkspaceListAction(filters);
  return (
    <div className="rounded-lg overflow-hidden border">
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
              <TableCell>{workspace.name ?? '-'}</TableCell>
              <TableCell>{workspace.slug ?? '-'}</TableCell>
              <TableCell>
                {format(new Date(workspace.created_at), 'PPpp')}
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
