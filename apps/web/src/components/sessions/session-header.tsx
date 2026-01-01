"use client";

import {
  GitBranch,
  Laptop,
  Pause,
  Play,
  Square,
  Wifi,
  WifiOff,
} from "lucide-react";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

interface SessionHeaderProps {
  repositoryName: string;
  branchName: string;
  deviceName: string;
  status: "active" | "paused" | "ended";
  isConnected: boolean;
  onPause?: () => void;
  onResume?: () => void;
  onTerminate?: () => void;
}

export function SessionHeader({
  repositoryName,
  branchName,
  deviceName,
  status,
  isConnected,
  onPause,
  onResume,
  onTerminate,
}: SessionHeaderProps) {
  return (
    <div className="flex items-center justify-between border-b px-4 py-3">
      <div className="flex items-center gap-4">
        {/* Repository info */}
        <div>
          <h2 className="font-semibold">{repositoryName}</h2>
          <div className="flex items-center gap-2 text-muted-foreground text-sm">
            <GitBranch className="h-3 w-3" />
            <span>{branchName}</span>
            <span>·</span>
            <Laptop className="h-3 w-3" />
            <span>{deviceName}</span>
          </div>
        </div>

        {/* Status badges */}
        <div className="flex items-center gap-2">
          <Badge
            variant={
              status === "active"
                ? "default"
                : status === "paused"
                  ? "secondary"
                  : "outline"
            }
          >
            {status === "active"
              ? "Active"
              : status === "paused"
                ? "Paused"
                : "Ended"}
          </Badge>
          {isConnected ? (
            <Badge className="gap-1" variant="outline">
              <Wifi className="h-3 w-3" />
              Connected
            </Badge>
          ) : (
            <Badge className="gap-1" variant="destructive">
              <WifiOff className="h-3 w-3" />
              Disconnected
            </Badge>
          )}
        </div>
      </div>

      {/* Controls */}
      {status !== "ended" && (
        <div className="flex items-center gap-2">
          {status === "active" ? (
            <Button onClick={onPause} size="sm" variant="outline">
              <Pause className="mr-1 h-4 w-4" />
              Pause
            </Button>
          ) : (
            <Button onClick={onResume} size="sm" variant="outline">
              <Play className="mr-1 h-4 w-4" />
              Resume
            </Button>
          )}

          <AlertDialog>
            <AlertDialogTrigger asChild>
              <Button size="sm" variant="destructive">
                <Square className="mr-1 h-4 w-4" />
                Terminate
              </Button>
            </AlertDialogTrigger>
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>Terminate Session?</AlertDialogTitle>
                <AlertDialogDescription>
                  This will end the Claude Code session and stop all running
                  operations. Any uncommitted changes will be preserved in the
                  worktree.
                </AlertDialogDescription>
              </AlertDialogHeader>
              <AlertDialogFooter>
                <AlertDialogCancel>Cancel</AlertDialogCancel>
                <AlertDialogAction
                  className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
                  onClick={onTerminate}
                >
                  Terminate
                </AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
        </div>
      )}
    </div>
  );
}
