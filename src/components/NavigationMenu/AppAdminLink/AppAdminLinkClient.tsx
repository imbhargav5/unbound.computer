"use client";
import { Link } from "@/components/intl-link";
import { classNames } from "@/utils/classNames";
import { Server } from "lucide-react";
import { usePathname } from "next/navigation";
import { match } from "path-to-regexp";

const matchAppAdmin = match("/app_admin/(.*)?");
export function AppAdminLinkClient() {
  const pathname = usePathname();
  const isActive = pathname ? matchAppAdmin(pathname) : false;

  return (
    <Link
      href="/app_admin"
      data-testid="admin-panel-link"
      className={classNames(
        `flex gap-1.5 py-1.5 px-3 cursor-pointer items-center group rounded-md transition hover:cursor-pointer hover:bg-neutral-100`,
        isActive ? "bg-neutral-100" : "bg-transparent",
      )}
    >
      <span
        className={classNames(
          "text-neutral-700",
          isActive ? "text-neutral-700" : "text-neutral-500",
        )}
      >
        <Server className="h-4 w-4" />
      </span>

      <span
        className={classNames(
          "transition text-sm font-normal whitespace-nowrap",
          isActive ? "text-neutral-700" : "text-neutral-500",
        )}
      >
        Admin Panel
      </span>
    </Link>
  );
}
