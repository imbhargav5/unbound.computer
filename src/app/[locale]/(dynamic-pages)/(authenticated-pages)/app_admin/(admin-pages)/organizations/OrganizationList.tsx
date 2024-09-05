'use server';
import {
  Table as ShadcnTable,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { getPaginatedOrganizationList } from '@/data/admin/organizations';
import { format } from 'date-fns';
import { Mail } from 'lucide-react';
import Link from 'next/link';
import { AppAdminOrganizationsFiltersSchema } from './schema';

export async function OrganizationList({
  filters,
}: {
  filters: AppAdminOrganizationsFiltersSchema;
}) {
  const organizations = await getPaginatedOrganizationList(filters);
  return (
    <div className="rounded-lg overflow-hidden border">
      <ShadcnTable>
        <TableHeader>
          <TableRow>
            <TableHead>Title</TableHead>
            <TableHead>Created At</TableHead>
            <TableHead>Team Member Count</TableHead>

            <TableHead>Owner Name</TableHead>

            <TableHead>Actions</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {organizations.map((organization) => (
            <TableRow key={organization.id}>
              <TableCell>{organization.title ?? '-'}</TableCell>
              <TableCell>
                {format(new Date(organization.created_at), 'PPpp')}
              </TableCell>
              <TableCell>{organization.team_members_count ?? '-'}</TableCell>
              <TableCell>{organization.owner_full_name}</TableCell>

              <TableCell>
                <span className="flex items-center space-x-2">
                  <Link
                    title="Send email"
                    href={`mailto:${organization.owner_email}`}
                    target="_blank"
                  >
                    <Mail className="w-5 h-5" />
                  </Link>
                </span>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </ShadcnTable>
    </div>
  );
}
