import "server-only";
import { cookies } from "next/headers";
import { connection } from "next/server";
import { Suspense } from "react";
import { SidebarProvider } from "./ui/sidebar";

export async function SidebarProviderWithStateContent({
  children,
}: {
  children: React.ReactNode;
}) {
  await connection();
  const cookieStore = await cookies();
  const defaultOpen = cookieStore.get("sidebar_state")?.value === "true";
  return (
    <SidebarProvider defaultOpen={defaultOpen}>{children}</SidebarProvider>
  );
}

export async function SidebarProviderWithState({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <Suspense>
      <SidebarProviderWithStateContent>
        {children}
      </SidebarProviderWithStateContent>
    </Suspense>
  );
}
