import { isLoggedInUserAppAdmin } from '@/data/admin/security';
import { AppAdminLinkClient } from './AppAdminLinkClient';

export async function AppAdminLink() {
  const isUserAppAdmin = await isLoggedInUserAppAdmin();
  return (
    <>{isUserAppAdmin ? <AppAdminLinkClient /> : null}</>
  );
}
