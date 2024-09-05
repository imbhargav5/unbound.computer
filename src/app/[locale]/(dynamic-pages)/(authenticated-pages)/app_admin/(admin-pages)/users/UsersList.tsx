'use server';

import { T } from '@/components/ui/Typography';
import {
  Table as ShadcnTable,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { getPaginatedUserList } from '@/data/admin/user';
import { format } from 'date-fns';
import { Check, Mail, X } from 'lucide-react';
import Link from 'next/link';
import { Suspense } from 'react';
import { ConfirmSendLoginLinkDialog } from './ConfirmSendLoginLinkDialog';
import { GetLoginLinkDialog } from './GetLoginLinkDialog';
import { AppAdminUserFiltersSchema } from './schema';
export async function UserList({
  filters,
}: {
  filters: AppAdminUserFiltersSchema;
}) {
  const users = await getPaginatedUserList(filters);
  return (
    <div className="space-y-2 border">
      <ShadcnTable>
        <TableHeader>
          <TableRow>
            <TableHead>Full Name</TableHead>
            <TableHead>Email</TableHead>
            <TableHead>Admin</TableHead>
            <TableHead>Created At</TableHead>
            <TableHead>Confirmed</TableHead>
            <TableHead>Contact User</TableHead>
            <TableHead>Send Login Link</TableHead>
            <TableHead>Debug</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {users.map((user) => (
            <TableRow key={user.id}>
              <TableCell> {user.full_name ?? '-'} </TableCell>
              <TableCell>
                <Link href={`/app_admin/users/${user.id}`}>{user.email}</Link>
              </TableCell>
              <TableCell>
                {user.is_app_admin ? (
                  <Check className="text-green-500 dark:text-green-400" />
                ) : (
                  <X className="text-red-500 dark:text-red-400" />
                )}
              </TableCell>
              <TableCell>{format(new Date(user.created_at), 'PPpp')}</TableCell>
              <TableCell>
                {user.is_confirmed ? (
                  <Check className="text-green-500 dark:text-green-400" />
                ) : (
                  <X className="text-red-500 dark:text-red-400" />
                )}
              </TableCell>
              <TableCell>
                <span className="flex items-center space-x-4">
                  <a
                    title="Contact User by email"
                    className="flex items-center "
                    href={`mailto:${user.email}`}
                    target="_blank"
                    rel="noreferrer"
                  >
                    <Mail className="h-5 w-5 mr-2 " />{' '}
                    <T.Small className=" font-medium underline underline-offset-4 ">
                      Contact User by email
                    </T.Small>
                  </a>
                </span>
              </TableCell>

              <TableCell>
                <Suspense>
                  <ConfirmSendLoginLinkDialog userEmail={user.email} />
                </Suspense>
              </TableCell>
              <TableCell>
                <Suspense>
                  <GetLoginLinkDialog userId={user.id} />
                </Suspense>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </ShadcnTable>
    </div>
  );
}
