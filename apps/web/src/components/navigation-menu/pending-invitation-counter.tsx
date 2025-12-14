"use server";

import { Mail } from "lucide-react";
import { Link } from "@/components/intl-link";
import { Badge } from "@/components/ui/badge";
import { getPendingInvitationCountOfUser } from "@/data/user/invitation";

export async function PendingInvitationCounter() {
  const count = await getPendingInvitationCountOfUser();
  if (count) {
    return (
      <Link href="/user/invitations">
        <Badge className="h-fit w-max rounded-md px-3 py-2" variant="secondary">
          <Mail className="mr-2 h-4 w-4" />
          {count} pending invites
        </Badge>
      </Link>
    );
  }
  return null;
}
