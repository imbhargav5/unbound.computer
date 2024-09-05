import { Skeleton } from '@/components/ui/skeleton';
import {
  Table as ShadcnTable,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { getSlimOrganizationsOfUser } from '@/data/admin/organizations';
import { Suspense } from 'react';
import { z } from 'zod';

const paramsSchema = z.object({
  userId: z.string(),
});

async function OrganizationsTable({ userId }: { userId: string }) {
  const organizationsForUser = await getSlimOrganizationsOfUser(userId);

  return (
    <div className="space-y-4">
      <ShadcnTable>
        <TableHeader>
          <TableRow>
            <TableHead>Organization Name</TableHead>
            <TableHead>Role</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {organizationsForUser.map((org) => (
            <TableRow key={org.id}>
              <TableCell>{org.title}</TableCell>
              <TableCell>{org.member_role}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </ShadcnTable>
    </div>
  );
}

export default async function AdminUserPage({ params }: { params: unknown }) {
  const { userId } = paramsSchema.parse(params);

  return (
    <Suspense fallback={<Skeleton className="w-full h-6" />}>
      <OrganizationsTable userId={userId} />
    </Suspense>
  );
}
