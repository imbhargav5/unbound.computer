import { Separator } from "@/components/ui/separator";
import { T } from "@/components/ui/Typography";
import { NotificationPageContent } from "./NotificationPageContent";

export const metadata = {
  title: "Notifications",
  description: "View and manage your notifications",
};

export default function NotificationsPage() {
  return (
    <div className="container max-w-5xl py-8 space-y-8">
      <div className="space-y-2">
        <T.H2>Notifications</T.H2>
        <T.P className="text-muted-foreground">
          Stay updated with all your activities and updates
        </T.P>
      </div>
      <Separator />
      <NotificationPageContent />
    </div>
  );
}
