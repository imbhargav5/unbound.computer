import { ExternalNavigation } from "@/components/navigation-menu/external-navbar/external-navigation";
import "./layout.css";

export default async function Layout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="dark min-h-screen bg-black">
      <ExternalNavigation />
      {children}
    </div>
  );
}
