"use client";
import { usePostHog } from "posthog-js/react";
import { useDidMount } from "rooks";
import { T } from "@/components/type-system";
import { useRouter } from "@/i18n/navigation";
import { supabaseUserClientComponent } from "@/supabase-clients/user/supabase-user-client-component";

export function LogoutClient() {
  const router = useRouter();
  const posthog = usePostHog();
  useDidMount(async () => {
    await supabaseUserClientComponent.auth.signOut();
    router.refresh();
    router.replace("/");
    posthog.reset();
  });
  return <T.Subtle>Signing out...</T.Subtle>;
}
