"use client";

import { formatDistanceToNow } from "date-fns";
import { Globe, Loader2 } from "lucide-react";
import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

interface WebSession {
  authorized_at: string | null;
  authorizing_device: {
    id: string;
    name: string;
    device_type: string;
  } | null;
  created_at: string;
  expires_at: string;
  id: string;
  ip_address: unknown; // INET type from PostgreSQL
  status: string;
  user_agent: string | null;
}

function getBrowserName(userAgent: string | null): string {
  if (!userAgent) return "Unknown browser";
  if (userAgent.includes("Chrome")) return "Chrome";
  if (userAgent.includes("Firefox")) return "Firefox";
  if (userAgent.includes("Safari")) return "Safari";
  if (userAgent.includes("Edge")) return "Edge";
  return "Browser";
}

export function WebSessionsList({ sessions }: { sessions: WebSession[] }) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [revokingId, setRevokingId] = useState<string | null>(null);

  const handleRevoke = async (sessionId: string) => {
    setRevokingId(sessionId);
    try {
      const response = await fetch(`/api/v1/web/sessions/${sessionId}`, {
        method: "DELETE",
        credentials: "include",
      });

      if (response.ok) {
        startTransition(() => {
          router.refresh();
        });
      }
    } finally {
      setRevokingId(null);
    }
  };

  if (sessions.length === 0) {
    return (
      <Card>
        <CardContent className="py-8 text-center text-muted-foreground">
          <p>No active web sessions.</p>
          <p className="mt-2 text-sm">
            Web sessions allow you to access your coding sessions from a
            browser.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      {sessions.map((session) => {
        const isExpired = new Date(session.expires_at) < new Date();
        const isRevoking = revokingId === session.id;

        return (
          <Card key={session.id}>
            <CardHeader className="pb-2">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <Globe className="h-5 w-5" />
                  <div>
                    <CardTitle className="text-base">
                      {getBrowserName(session.user_agent)}
                    </CardTitle>
                    <CardDescription>
                      {session.ip_address
                        ? String(session.ip_address)
                        : "Unknown IP"}
                    </CardDescription>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <Badge
                    variant={
                      session.status === "active"
                        ? "default"
                        : session.status === "pending"
                          ? "outline"
                          : "secondary"
                    }
                  >
                    {session.status === "pending"
                      ? "Waiting for authorization"
                      : session.status}
                  </Badge>
                  {isExpired && <Badge variant="destructive">Expired</Badge>}
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="flex items-center justify-between">
                <div className="text-muted-foreground text-sm">
                  {session.authorized_at ? (
                    <span>
                      Authorized{" "}
                      {formatDistanceToNow(new Date(session.authorized_at), {
                        addSuffix: true,
                      })}
                      {session.authorizing_device && (
                        <span> by {session.authorizing_device.name}</span>
                      )}
                    </span>
                  ) : (
                    <span>
                      Created{" "}
                      {formatDistanceToNow(new Date(session.created_at), {
                        addSuffix: true,
                      })}
                    </span>
                  )}
                  <span className="mx-2">·</span>
                  <span>
                    Expires{" "}
                    {formatDistanceToNow(new Date(session.expires_at), {
                      addSuffix: true,
                    })}
                  </span>
                </div>
                <Button
                  disabled={isRevoking || isPending}
                  onClick={() => handleRevoke(session.id)}
                  size="sm"
                  variant="outline"
                >
                  {isRevoking ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : (
                    "Revoke"
                  )}
                </Button>
              </div>
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}
