"use client";

import { formatDistanceToNow } from "date-fns";
import {
  GitBranch,
  Laptop,
  Monitor,
  Pause,
  Play,
  Server,
  Smartphone,
} from "lucide-react";
import { Link } from "@/components/intl-link";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import type { getSessionHistory } from "@/data/user/coding-sessions";

type CodingSession = Awaited<ReturnType<typeof getSessionHistory>>[number];

function getDeviceIcon(deviceType: string) {
  switch (deviceType) {
    case "mac-desktop":
      return <Laptop className="h-4 w-4" />;
    case "win-desktop":
      return <Monitor className="h-4 w-4" />;
    case "linux-desktop":
      return <Server className="h-4 w-4" />;
    case "ios-phone":
    case "android-phone":
      return <Smartphone className="h-4 w-4" />;
    default:
      return <Laptop className="h-4 w-4" />;
  }
}

function getStatusIcon(status: string) {
  switch (status) {
    case "active":
      return <Play className="h-3 w-3" />;
    case "paused":
      return <Pause className="h-3 w-3" />;
    default:
      return null;
  }
}

function getStatusVariant(
  status: string
): "default" | "secondary" | "outline" | "destructive" {
  switch (status) {
    case "active":
      return "default";
    case "paused":
      return "outline";
    case "ended":
      return "secondary";
    default:
      return "secondary";
  }
}

export function SessionsList({ sessions }: { sessions: CodingSession[] }) {
  if (sessions.length === 0) {
    return (
      <Card>
        <CardContent className="py-8 text-center text-muted-foreground">
          <p>No coding sessions yet.</p>
          <p className="mt-2 text-sm">
            Start a Claude Code session from your terminal to see it here.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      {sessions.map((session) => {
        const device = session.device;
        const repository = session.repository;

        return (
          <Link
            className="block transition-opacity hover:opacity-80"
            href={`/session/${session.id}`}
            key={session.id}
          >
            <Card>
              <CardHeader className="pb-2">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="flex items-center gap-2">
                      {device && getDeviceIcon(device.device_type)}
                      <div>
                        <CardTitle className="text-base">
                          {repository?.name ?? "Unknown Repository"}
                        </CardTitle>
                        <CardDescription>
                          {device?.name ?? "Unknown Device"}
                        </CardDescription>
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    {session.current_branch && (
                      <Badge className="gap-1" variant="outline">
                        <GitBranch className="h-3 w-3" />
                        {session.current_branch}
                      </Badge>
                    )}
                    <Badge
                      className="gap-1 capitalize"
                      variant={getStatusVariant(session.status)}
                    >
                      {getStatusIcon(session.status)}
                      {session.status}
                    </Badge>
                  </div>
                </div>
              </CardHeader>
              <CardContent>
                <div className="text-muted-foreground text-sm">
                  <span>
                    Started{" "}
                    {formatDistanceToNow(new Date(session.session_started_at), {
                      addSuffix: true,
                    })}
                  </span>
                  {session.session_ended_at && (
                    <>
                      <span className="mx-2">·</span>
                      <span>
                        Ended{" "}
                        {formatDistanceToNow(
                          new Date(session.session_ended_at),
                          {
                            addSuffix: true,
                          }
                        )}
                      </span>
                    </>
                  )}
                </div>
              </CardContent>
            </Card>
          </Link>
        );
      })}
    </div>
  );
}
