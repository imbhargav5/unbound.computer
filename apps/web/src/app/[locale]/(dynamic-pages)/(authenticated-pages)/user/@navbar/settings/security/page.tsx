import { T } from "@/components/ui/typography-ui";
import { cn } from "@/utils/cn";

export default function InvitationsNavbar() {
  return (
    <div className={cn("hidden lg:block", "relative")}>
      <T.P className="my-0">Security Settings</T.P>
    </div>
  );
}
