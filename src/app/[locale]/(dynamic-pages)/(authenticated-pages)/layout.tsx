import { Skeleton } from '@/components/ui/skeleton';
import { SIDEBAR_VISIBILITY_COOKIE_KEY } from '@/constants';
import { CreateWorkspaceDialogProvider } from '@/contexts/CreateWorkspaceDialogContext';
import { LoggedInUserProvider } from '@/contexts/LoggedInUserContext';
import { SidebarVisibilityProvider } from '@/contexts/SidebarVisibilityContext';
import { serverGetLoggedInUserVerified } from '@/utils/server/serverGetLoggedInUser';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
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
  try {
    const user = await serverGetLoggedInUserVerified();
    const sidebarVisibility = getSidebarVisibility();
    return (
      <SidebarVisibilityProvider initialValue={sidebarVisibility}>
        <CreateWorkspaceDialogProvider>
          <LoggedInUserProvider user={user}>
            <ClientLayout>
              {children}
            </ClientLayout>
          </LoggedInUserProvider>
        </CreateWorkspaceDialogProvider>
      </SidebarVisibilityProvider>
    );
  } catch (fetchDataError) {
    console.log('fetchDataError', fetchDataError);
    redirect('/login');
    return null;
  }
}

export default async function Layout({ children }: { children: ReactNode }) {
  return (
    <Suspense fallback={<Skeleton className="w-16 h-6" />}>
      <AuthenticatedLayout>{children}</AuthenticatedLayout>
    </Suspense>
  );
}
