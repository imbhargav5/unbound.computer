import { ReactNode } from "react";
import { ClientShell } from "./ClientShell";

export async function ApplicationLayoutShell({
  children,
  sidebar,
}: {
  children: ReactNode;
  sidebar: ReactNode;
}) {
  return <ClientShell sidebar={sidebar}>{children}</ClientShell>;
}
