import { isLoggedInUserAppAdmin } from '@/data/admin/security';
import { AppAdminLinkClient } from './AppAdminLinkClient';

export async function AppAdminLink() {
  const isUserAppAdmin = await isLoggedInUserAppAdmin();
  console.log('isUserAppAdmin', isUserAppAdmin);
  return (
    <>{isUserAppAdmin ? <AppAdminLinkClient /> : null}</>
  );
}
