"use client";

import { formatDistanceToNow } from "date-fns";
import { Laptop, Monitor, Server } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

interface Device {
  id: string;
  name: string;
  device_type: string;
  hostname: string | null;
  is_active: boolean;
  last_seen_at: string | null;
  created_at: string;
}

function getDeviceIcon(deviceType: string) {
  switch (deviceType) {
    case "mac":
      return <Laptop className="h-5 w-5" />;
    case "linux":
      return <Server className="h-5 w-5" />;
    case "windows":
      return <Monitor className="h-5 w-5" />;
    default:
      return <Laptop className="h-5 w-5" />;
  }
}

function isOnline(lastSeenAt: string | null): boolean {
  if (!lastSeenAt) return false;
  const lastSeen = new Date(lastSeenAt);
  const now = new Date();
  // Consider online if seen within last 2 minutes
  return now.getTime() - lastSeen.getTime() < 2 * 60 * 1000;
}

export function DevicesList({ devices }: { devices: Device[] }) {
  if (devices.length === 0) {
    return (
      <Card>
        <CardContent className="py-8 text-center text-muted-foreground">
          <p>No devices registered yet.</p>
          <p className="mt-2 text-sm">
            Install the CLI and run{" "}
            <code className="rounded bg-muted px-1">unbound link</code> to
            register a device.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      {devices.map((device) => {
        const online = isOnline(device.last_seen_at);
        return (
          <Card key={device.id}>
            <CardHeader className="pb-2">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  {getDeviceIcon(device.device_type)}
                  <div>
                    <CardTitle className="text-base">{device.name}</CardTitle>
                    <CardDescription>
                      {device.hostname ?? device.device_type}
                    </CardDescription>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <Badge variant={online ? "default" : "secondary"}>
                    {online ? "Online" : "Offline"}
                  </Badge>
                  {!device.is_active && (
                    <Badge variant="destructive">Inactive</Badge>
                  )}
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="text-muted-foreground text-sm">
                {device.last_seen_at ? (
                  <span>
                    Last seen{" "}
                    {formatDistanceToNow(new Date(device.last_seen_at), {
                      addSuffix: true,
                    })}
                  </span>
                ) : (
                  <span>Never connected</span>
                )}
                <span className="mx-2">·</span>
                <span>
                  Registered{" "}
                  {formatDistanceToNow(new Date(device.created_at), {
                    addSuffix: true,
                  })}
                </span>
              </div>
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}
