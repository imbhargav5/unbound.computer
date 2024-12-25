import { PublicNavigation } from "@/components/NavigationMenu/PublicNavbar.tsx/PublicNavigation";

export default function PublicLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <>
      <PublicNavigation />
      {children}
    </>
  );
}
