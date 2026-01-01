import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { createSupabaseUserServerComponentClient } from "@/supabase-clients/user/create-supabase-user-server-component-client";
import { DevicesList } from "./devices-list";
import { WebSessionsList } from "./web-sessions-list";

export const metadata = {
  title: "Devices",
  description: "Manage your devices and web sessions",
};

async function DevicesContent() {
  const supabase = await createSupabaseUserServerComponentClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return <div>Please log in to view your devices.</div>;
  }

  const { data: devices } = await supabase
    .from("devices")
    .select("*")
    .eq("user_id", user.id)
    .order("last_seen_at", { ascending: false });

  const { data: webSessions } = await supabase
    .from("web_sessions")
    .select(
      `
      *,
      authorizing_device:devices!web_sessions_authorizing_device_id_fkey(id, name, device_type)
    `
    )
    .eq("user_id", user.id)
    .in("status", ["pending", "active"])
    .order("created_at", { ascending: false });

  return (
    <div className="space-y-8">
      <section>
        <h2 className="mb-4 font-semibold text-xl">Registered Devices</h2>
        <DevicesList devices={devices ?? []} />
      </section>

      <section>
        <h2 className="mb-4 font-semibold text-xl">Active Web Sessions</h2>
        <WebSessionsList sessions={webSessions ?? []} />
      </section>
    </div>
  );
}

export default function DevicesPage() {
  return (
    <div className="container max-w-4xl py-8">
      <div className="mb-8">
        <h1 className="font-bold text-2xl">Devices & Sessions</h1>
        <p className="text-muted-foreground">
          Manage your registered devices and active web sessions.
        </p>
      </div>

      <Suspense
        fallback={
          <div className="space-y-4">
            <Skeleton className="h-32 w-full" />
            <Skeleton className="h-32 w-full" />
          </div>
        }
      >
        <DevicesContent />
      </Suspense>
    </div>
  );
}
