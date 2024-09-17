'use client';
import { T } from '@/components/ui/Typography';
import { supabaseUserClientComponent } from '@/supabase-clients/user/supabaseUserClientComponent';
import { useRouter } from 'next/navigation';
import { useDidMount } from 'rooks';

export default function Logout() {
  const router = useRouter();
  useDidMount(async () => {
    await supabaseUserClientComponent.auth.signOut();
    router.refresh();
    router.replace('/');
  });

  return <T.P>Signing out...</T.P>;
}
