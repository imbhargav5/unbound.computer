"use client";
import { Computer, Lock, User } from "lucide-react";
import { useMemo } from "react";
import { PageHeading } from "@/components/page-heading";
import { TabsNavigation } from "@/components/tabs-navigation";

export default function UserSettingsClientLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const tabs = useMemo(
    () => [
      {
        label: "Account Settings",
        href: "/user/settings",
        icon: <User />,
      },
      {
        label: "Developer Settings",
        href: "/user/settings/developer",
        icon: <Computer />,
      },
      {
        label: "Security",
        href: "/user/settings/security",
        icon: <Lock />,
      },
    ],
    []
  );

  return (
    <div className="space-y-6">
      <PageHeading
        subTitle="Manage your account and security settings here."
        title="User Settings"
      />
      <TabsNavigation tabs={tabs} />
      {children}
    </div>
  );
}
