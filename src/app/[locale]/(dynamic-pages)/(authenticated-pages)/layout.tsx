import { NotificationsDialog } from "@/components/notifications-dialog";
import { CreateWorkspaceDialogProvider } from "@/contexts/CreateWorkspaceDialogContext";
import { LoggedInUserProvider } from "@/contexts/LoggedInUserContext";
import { NotificationsProvider } from "@/contexts/NotificationsContext";
import { serverGetLoggedInUserVerified } from "@/utils/server/serverGetLoggedInUser";
import { redirect } from "next/navigation";
import { type ReactNode } from "react";
import { ClientLayout } from "./ClientLayout";

export default async function Layout({ children }: { children: ReactNode }) {
  try {
    const user = await serverGetLoggedInUserVerified();
    return (
      <CreateWorkspaceDialogProvider>
        <LoggedInUserProvider user={user}>
          <NotificationsProvider>
            <ClientLayout>{children}</ClientLayout>
            <NotificationsDialog />
          </NotificationsProvider>
        </LoggedInUserProvider>
      </CreateWorkspaceDialogProvider>
    );
  } catch (fetchDataError) {
    console.log("fetchDataError", fetchDataError);
    redirect("/login");
    return null;
  }
}
