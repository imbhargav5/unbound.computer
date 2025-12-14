import { Bug, MessageSquare, Zap } from "lucide-react";
import type { Enum } from "@/types";

export function getTypeIcon(
  type: Enum<"marketing_feedback_thread_type">
): React.ReactNode {
  switch (type) {
    case "bug":
      return <Bug className="h-3 w-3" />;
    case "feature_request":
      return <Zap className="h-3 w-3" />;
    case "general":
      return <MessageSquare className="h-3 w-3" />;
  }
}
