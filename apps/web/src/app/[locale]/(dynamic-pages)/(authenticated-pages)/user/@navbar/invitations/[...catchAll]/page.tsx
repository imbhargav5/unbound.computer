import { ArrowLeftIcon } from "@radix-ui/react-icons";
import { Link } from "@/components/intl-link";
import { T } from "@/components/ui/typography-ui";
import { cn } from "@/utils/cn";

export default function InvitationsNavbar() {
  return (
    <div className={cn("hidden lg:block", "relative")}>
      <T.P className="my-0">
        <Link href="/user/invitations">
          <span className="flex items-center space-x-2">
            <ArrowLeftIcon />
            <span>Back to Invitations</span>
          </span>
        </Link>
      </T.P>
    </div>
  );
}
