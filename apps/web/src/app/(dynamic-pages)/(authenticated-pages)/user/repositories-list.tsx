"use client";

import { formatDistanceToNow } from "date-fns";
import {
  FolderGit2,
  GitBranch,
  Laptop,
  Monitor,
  Server,
  Smartphone,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import type { getUserRepositories } from "@/data/user/repositories";

type Repository = Awaited<ReturnType<typeof getUserRepositories>>[number];

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

export function RepositoriesList({
  repositories,
}: {
  repositories: Repository[];
}) {
  if (repositories.length === 0) {
    return (
      <Card>
        <CardContent className="py-8 text-center text-muted-foreground">
          <p>No repositories registered yet.</p>
          <p className="mt-2 text-sm">
            Repositories are automatically registered when you start a coding
            session.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="space-y-3">
      {repositories.map((repo) => {
        const activeSessions = Array.isArray(repo.active_sessions)
          ? repo.active_sessions
          : repo.active_sessions
            ? [repo.active_sessions]
            : [];
        const worktrees = Array.isArray(repo.worktrees)
          ? repo.worktrees
          : repo.worktrees
            ? [repo.worktrees]
            : [];
        const activeCount = activeSessions.filter(
          (s) => s.status === "active"
        ).length;

        return (
          <Card key={repo.id}>
            <CardHeader className="pb-2">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <FolderGit2 className="h-5 w-5 text-muted-foreground" />
                  <div>
                    <CardTitle className="text-base">{repo.name}</CardTitle>
                    <CardDescription className="flex items-center gap-2">
                      {repo.device && (
                        <span className="flex items-center gap-1">
                          {getDeviceIcon(repo.device.device_type)}
                          {repo.device.name}
                        </span>
                      )}
                    </CardDescription>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  {repo.default_branch && (
                    <Badge className="gap-1" variant="outline">
                      <GitBranch className="h-3 w-3" />
                      {repo.default_branch}
                    </Badge>
                  )}
                  {activeCount > 0 && (
                    <Badge variant="default">
                      {activeCount} active{" "}
                      {activeCount === 1 ? "session" : "sessions"}
                    </Badge>
                  )}
                  {worktrees.length > 0 && (
                    <Badge variant="secondary">
                      {worktrees.length}{" "}
                      {worktrees.length === 1 ? "worktree" : "worktrees"}
                    </Badge>
                  )}
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="text-muted-foreground text-sm">
                {repo.remote_url && (
                  <>
                    <span className="font-mono text-xs">{repo.remote_url}</span>
                    <span className="mx-2">·</span>
                  </>
                )}
                <span>
                  Updated{" "}
                  {formatDistanceToNow(new Date(repo.updated_at), {
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
