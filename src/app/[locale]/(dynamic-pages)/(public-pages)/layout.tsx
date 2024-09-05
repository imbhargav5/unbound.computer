import { PublicNavigation } from '@/components/NavigationMenu/PublicNavbar.tsx/PublicNavigation';


export default function PublicLayout({ children }) {
  return (
    <>
      <PublicNavigation />
      {children}
    </>
  );
}
