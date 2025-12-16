import { ExternalNavigation } from "@/components/navigation-menu/external-navbar/external-navigation";
import "./layout.css";

export default async function Layout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div>
      <ExternalNavigation />
      {children}
    </div>
  );
}
