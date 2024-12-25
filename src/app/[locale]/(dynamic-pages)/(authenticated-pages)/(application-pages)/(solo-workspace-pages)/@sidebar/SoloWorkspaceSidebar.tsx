// OrganizationSidebar.tsx (Server Component)

import { SidebarAdminPanelNav } from "@/components/sidebar-admin-panel-nav";
import { SwitcherAndToggle } from "@/components/sidebar-components/switcher-and-toggle";
import { SidebarFooterUserNav } from "@/components/sidebar-footer-user-nav";
import { SidebarPlatformNav } from "@/components/sidebar-platform-nav";
import { SidebarTipsNav } from "@/components/sidebar-tips-nav";
import { SidebarWorkspaceNav } from "@/components/sidebar-workspace-nav";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarRail,
} from "@/components/ui/sidebar";
import { SubscriptionData } from "@/payments/AbstractPaymentGateway";
import { StripePaymentGateway } from "@/payments/StripePaymentGateway";
import {
  getCachedSlimWorkspaces,
  getCachedSoloWorkspace,
} from "@/rsc-data/user/workspaces";
import { toLower } from "lodash";
import { notFound } from "next/navigation";

function getHasProSubscription(subscriptions: SubscriptionData[]) {
  return subscriptions.some(
    (subscription) =>
      toLower(subscription.billing_products?.name).includes("pro") &&
      subscription.billing_products?.active,
  );
}

export async function SoloWorkspaceSidebar() {
  try {
    const paymentGateway = new StripePaymentGateway();
    const [workspace, slimWorkspaces] = await Promise.all([
      getCachedSoloWorkspace(),
      getCachedSlimWorkspaces(),
    ]);
    const subscriptions = await paymentGateway.db.getSubscriptionsByWorkspaceId(
      workspace.id,
    );
    const hasProSubscription = getHasProSubscription(subscriptions);

    return (
      <Sidebar variant="inset" collapsible="icon">
        <SidebarHeader>
          <SwitcherAndToggle
            workspaceId={workspace.id}
            slimWorkspaces={slimWorkspaces}
          />
        </SidebarHeader>
        <SidebarContent>
          <SidebarWorkspaceNav workspace={workspace} />
          <SidebarAdminPanelNav />
          <SidebarPlatformNav />
          <SidebarTipsNav workspace={workspace} />
        </SidebarContent>
        <SidebarFooter>
          <SidebarFooterUserNav />
        </SidebarFooter>
        <SidebarRail />
      </Sidebar>
    );
  } catch (e) {
    return notFound();
  }
}
