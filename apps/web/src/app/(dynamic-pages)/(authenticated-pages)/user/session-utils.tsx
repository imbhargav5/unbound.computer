import {
  GitBranch,
  Laptop,
  Monitor,
  Pause,
  Play,
  Server,
  Smartphone,
} from "lucide-react";

export function getDeviceIcon(deviceType: string) {
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

export function getStatusIcon(status: string) {
  switch (status) {
    case "active":
      return <Play className="h-3 w-3" />;
    case "paused":
      return <Pause className="h-3 w-3" />;
    default:
      return null;
  }
}

export function getStatusVariant(
  status: string,
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

export function getBranchIcon() {
  return <GitBranch className="h-3 w-3" />;
}

export function getStatusDotColor(status: string): string {
  switch (status) {
    case "active":
      return "bg-green-500";
    case "paused":
      return "bg-yellow-500";
    case "ended":
      return "bg-muted-foreground/50";
    default:
      return "bg-muted-foreground/50";
  }
}
