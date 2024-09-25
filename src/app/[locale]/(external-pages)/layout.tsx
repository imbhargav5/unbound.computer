import { ExternalNavigation } from '@/components/NavigationMenu/ExternalNavbar/ExternalNavigation';
import { routing } from '@/i18n/routing';
import './layout.css';
export const dynamic = 'force-static';
export const revalidate = 60;


export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}
export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <div>
      <ExternalNavigation />
      {children}
    </div>
  );
}
