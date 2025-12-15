import { unauthorized } from "next/navigation";
import { InternalNavbar } from "@/components/navigation-menu/internal-navbar";
import { SidebarProviderWithState } from "@/components/sidebar-provider-with-state";
import { SidebarInset } from "@/components/ui/sidebar";
import { isSupabaseUserClaimAppAdmin } from "@/utils/is-supabase-user-app-admin";
import { serverGetLoggedInUserClaims } from "@/utils/server/server-get-logged-in-user";

export default async function Layout({
  children,
  sidebar,
  navbar,
}: {
  children: React.ReactNode;
  sidebar: React.ReactNode;
  navbar: React.ReactNode;
}) {
  // this will only check the claims, not the user.
  // all of our mutations check the user privilege, so
  // it is safe to only check the claims here.
  const user = await serverGetLoggedInUserClaims();
  const isAppAdmin = isSupabaseUserClaimAppAdmin(user);
  if (!isAppAdmin) {
    return unauthorized();
  }
  return (
    <SidebarProviderWithState>
      {sidebar}
      <SidebarInset
        className="overflow-hidden"
        style={{
          maxHeight: "calc(100svh - 16px)",
        }}
      >
        <div className="overflow-y-auto">
          <div
            className="h-full overflow-y-auto"
            data-testid="admin-panel-layout"
          >
            <InternalNavbar>
              <div
                className="flex w-full items-center justify-start"
                data-testid="admin-panel-title"
              >
                {navbar}
              </div>
            </InternalNavbar>
            <div className="relative h-auto w-full flex-1">
              <div className="space-y-6 px-6 py-6">
                <p>
                  All sections of this area are protected and only accessible by
                  Application Admins.
                </p>
                {children}
              </div>
            </div>
          </div>
        </div>
      </SidebarInset>
    </SidebarProviderWithState>
  );
}
