import { serverGetLoggedInUser } from '@/utils/server/serverGetLoggedInUser';
import { UpdatePassword } from './UpdatePassword';

export default async function UpdatePasswordPage() {
  await serverGetLoggedInUser();
  return <UpdatePassword />;
}
