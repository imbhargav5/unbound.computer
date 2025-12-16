"use server";

import { format } from "date-fns";
import { Check, Mail, X } from "lucide-react";
import { Suspense } from "react";
import { Link } from "@/components/intl-link";
import {
  Table as ShadcnTable,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { T } from "@/components/ui/typography-ui";
import { getPaginatedUserListAction } from "@/data/admin/user";
import { ConfirmSendLoginLinkDialog } from "./confirm-send-login-link-dialog";
import { GetLoginLinkDialog } from "./get-login-link-dialog";
import type { AppAdminUserFiltersSchema } from "./schema";

export async function UserList({
  filters,
}: {
  filters: AppAdminUserFiltersSchema;
}) {
  const usersActionResult = await getPaginatedUserListAction(filters);
  if (usersActionResult?.data) {
    const users = usersActionResult.data;
    return (
      <div className="space-y-2">
        <ShadcnTable>
          <TableHeader>
            <TableRow>
              <TableHead>Full Name</TableHead>
              <TableHead>Email</TableHead>
              <TableHead>Admin</TableHead>
              <TableHead>Created At</TableHead>
              <TableHead>Contact User</TableHead>
              <TableHead>Send Login Link</TableHead>
              <TableHead>Debug</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {users.map((user) => {
              const isAppAdmin = user.user_roles.some(
                (role: { role: string }) => role.role === "admin"
              );
              const email =
                user.user_application_settings?.email_readonly ?? "-";

              return (
                <TableRow key={user.id}>
                  <TableCell> {user.full_name ?? "-"} </TableCell>
                  <TableCell>
                    <Link href={`/app-admin/users/${user.id}`}>{email}</Link>
                  </TableCell>
                  <TableCell>
                    {isAppAdmin ? (
                      <Check className="text-green-500 dark:text-green-400" />
                    ) : (
                      <X className="text-red-500 dark:text-red-400" />
                    )}
                  </TableCell>
                  <TableCell>
                    {format(new Date(user.created_at), "PPpp")}
                  </TableCell>

                  <TableCell>
                    <span className="flex items-center space-x-4">
                      <a
                        className="flex items-center"
                        href={`mailto:${email}`}
                        rel="noreferrer"
                        target="_blank"
                        title="Contact User by email"
                      >
                        <Mail className="mr-2 h-5 w-5" />{" "}
                        <T.Small className="font-medium underline underline-offset-4">
                          Contact User by email
                        </T.Small>
                      </a>
                    </span>
                  </TableCell>

                  <TableCell>
                    <Suspense>
                      <ConfirmSendLoginLinkDialog userEmail={email} />
                    </Suspense>
                  </TableCell>
                  <TableCell>
                    <Suspense>
                      <GetLoginLinkDialog userId={user.id} />
                    </Suspense>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </ShadcnTable>
      </div>
    );
  }
  if (usersActionResult?.serverError) {
    return <div>{usersActionResult.serverError}</div>;
  }
  console.error(usersActionResult);
  return <div>Failed to load users</div>;
}
