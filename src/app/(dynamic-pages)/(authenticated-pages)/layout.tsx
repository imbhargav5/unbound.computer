import { Skeleton } from '@/components/ui/skeleton';
import { SIDEBAR_VISIBILITY_COOKIE_KEY } from '@/constants';
import { LoggedInUserProvider } from '@/contexts/LoggedInUserContext';
import { SidebarVisibilityProvider } from '@/contexts/SidebarVisibilityContext';
import { errors } from '@/utils/errors';
import { serverGetLoggedInUser } from '@/utils/server/serverGetLoggedInUser';
import { cookies } from 'next/headers';
import { Suspense, type ReactNode } from 'react';
import { ClientLayout } from './ClientLayout';

function getSidebarVisibility() {
  const cookieStore = cookies();
  const cookieValue = cookieStore.get(SIDEBAR_VISIBILITY_COOKIE_KEY)?.value;
  if (cookieValue) {
    return cookieValue === 'true';
  }
  return true;
}

async function AuthenticatedLayout({ children }: { children: ReactNode }) {
  const user = await serverGetLoggedInUser();
  try {
    const sidebarVisibility = getSidebarVisibility();

    return (
      <SidebarVisibilityProvider initialValue={sidebarVisibility}>
        <LoggedInUserProvider user={user}>
          <ClientLayout >
            {children}
          </ClientLayout>
        </LoggedInUserProvider>
      </SidebarVisibilityProvider>
    );
  } catch (fetchDataError) {
    errors.add(fetchDataError);
    return <p>Error: An error occurred.</p>;
  }
}
export default async function Layout({ children }: { children: ReactNode }) {
  return (
    <Suspense fallback={<Skeleton className="w-16 h-6" />}>
      <AuthenticatedLayout>{children}</AuthenticatedLayout>
    </Suspense>
  );
}
