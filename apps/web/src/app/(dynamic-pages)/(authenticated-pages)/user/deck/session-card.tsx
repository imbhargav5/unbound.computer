"use client";

import { formatDistanceToNow } from "date-fns";
import { GitBranch } from "lucide-react";
import { Link } from "@/components/intl-link";
import { Badge } from "@/components/ui/badge";
import type { CardSize } from "@/hooks/use-deck-config";
import type { DeckSession } from "@/data/user/deck-sessions";
import {
  getDeviceIcon,
  getStatusDotColor,
  getStatusIcon,
  getStatusVariant,
} from "../session-utils";

type SessionCardProps = {
  session: DeckSession;
  size: CardSize;
};

function SmallSessionCard({ session }: { session: DeckSession }) {
  const title = session.title ?? session.current_branch ?? "Untitled";

  return (
    <Link
      className="block rounded-lg border bg-card p-3 transition-colors hover:bg-accent/50"
      href={`/session/${session.id}`}
    >
      <div className="flex items-center gap-2">
        <span
          className={`h-2 w-2 shrink-0 rounded-full ${getStatusDotColor(session.status)}`}
        />
        <span className="min-w-0 flex-1 truncate font-medium text-sm">
          {title}
        </span>
        <span className="shrink-0 text-muted-foreground text-xs">
          {formatDistanceToNow(new Date(session.session_started_at), {
            addSuffix: false,
          })}
        </span>
      </div>
    </Link>
  );
}

function MediumSessionCard({ session }: { session: DeckSession }) {
  const title = session.title ?? session.current_branch ?? "Untitled";
  const device = session.device;

  return (
    <Link
      className="block rounded-lg border bg-card p-4 transition-colors hover:bg-accent/50"
      href={`/session/${session.id}`}
    >
      <div className="flex items-center justify-between gap-2">
        <span className="min-w-0 flex-1 truncate font-medium text-sm">
          {title}
        </span>
        <Badge
          className="shrink-0 gap-1 capitalize"
          variant={getStatusVariant(session.status)}
        >
          {getStatusIcon(session.status)}
          {session.status}
        </Badge>
      </div>
      <div className="mt-2 flex items-center gap-3 text-muted-foreground text-xs">
        {device && (
          <span className="flex items-center gap-1">
            {getDeviceIcon(device.device_type)}
            {device.name}
          </span>
        )}
        {session.current_branch && (
          <span className="flex items-center gap-1">
            <GitBranch className="h-3 w-3" />
            {session.current_branch}
          </span>
        )}
      </div>
      <div className="mt-1.5 text-muted-foreground text-xs">
        Started{" "}
        {formatDistanceToNow(new Date(session.session_started_at), {
          addSuffix: true,
        })}
      </div>
    </Link>
  );
}

function LargeSessionCard({ session }: { session: DeckSession }) {
  const title = session.title ?? session.current_branch ?? "Untitled";
  const device = session.device;
  const repository = session.repository;

  return (
    <Link
      className="block rounded-lg border bg-card p-5 transition-colors hover:bg-accent/50"
      href={`/session/${session.id}`}
    >
      <div className="flex items-center justify-between gap-2">
        <div className="min-w-0 flex-1">
          <div className="truncate font-semibold text-sm">{title}</div>
          {repository && (
            <div className="mt-0.5 truncate text-muted-foreground text-xs">
              {repository.name}
            </div>
          )}
        </div>
        <Badge
          className="shrink-0 gap-1 capitalize"
          variant={getStatusVariant(session.status)}
        >
          {getStatusIcon(session.status)}
          {session.status}
        </Badge>
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-3 text-muted-foreground text-xs">
        {device && (
          <span className="flex items-center gap-1">
            {getDeviceIcon(device.device_type)}
            {device.name}
          </span>
        )}
        {session.current_branch && (
          <Badge className="gap-1" variant="outline">
            <GitBranch className="h-3 w-3" />
            {session.current_branch}
          </Badge>
        )}
      </div>
      <div className="mt-3 space-y-1 text-muted-foreground text-xs">
        <div>
          Started{" "}
          {formatDistanceToNow(new Date(session.session_started_at), {
            addSuffix: true,
          })}
        </div>
        {session.session_ended_at && (
          <div>
            Ended{" "}
            {formatDistanceToNow(new Date(session.session_ended_at), {
              addSuffix: true,
            })}
          </div>
        )}
        {session.worktree_path && (
          <div className="truncate font-mono">{session.worktree_path}</div>
        )}
      </div>
    </Link>
  );
}

export function SessionCard({ session, size }: SessionCardProps) {
  switch (size) {
    case "small":
      return <SmallSessionCard session={session} />;
    case "medium":
      return <MediumSessionCard session={session} />;
    case "large":
      return <LargeSessionCard session={session} />;
  }
}
