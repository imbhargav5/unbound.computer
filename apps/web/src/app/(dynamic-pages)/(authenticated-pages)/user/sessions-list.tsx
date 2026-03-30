"use client";

import { formatDistanceToNow } from "date-fns";
import { GitBranch } from "lucide-react";
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
import {
  getDeviceIcon,
  getStatusIcon,
  getStatusVariant,
} from "./session-utils";

type CodingSession = Awaited<ReturnType<typeof getSessionHistory>>[number];

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
                          },
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
