'use server';
import { cache } from 'react';
import { isSupabaseUserAppAdmin } from '../isSupabaseUserAppAdmin';
import { serverGetLoggedInUser } from './serverGetLoggedInUser';

type UserRole = 'admin' | 'user';

/**
 * This function returns the role of the logged in user.
 * You can use this to determine if the user is an admin or a regular user.
 * Based on this value you can show or hide certain UI elements.
 */
export const serverGetLoggedInUserRole = cache(async () => {
  const user = await serverGetLoggedInUser();
  if (isSupabaseUserAppAdmin(user)) {
    return 'admin' as UserRole;
  }
  // legacy conditions.
  return 'user' as UserRole;
});
