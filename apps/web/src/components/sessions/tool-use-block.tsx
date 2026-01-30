"use client";

import { ChevronDown, ChevronRight, Clock, Wrench } from "lucide-react";
import { useState } from "react";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import { CodeBlock } from "./code-block";
import type { ToolUse } from "./types";

interface ToolUseBlockProps {
  toolUse: ToolUse;
}

export function ToolUseBlock({ toolUse }: ToolUseBlockProps) {
  const [isExpanded, setIsExpanded] = useState(false);

  const getStatusColor = () => {
    switch (toolUse.status) {
      case "running":
        return "bg-blue-500";
      case "completed":
        return "bg-green-500";
      case "error":
        return "bg-red-500";
      default:
        return "bg-gray-500";
    }
  };

  return (
    <div className="overflow-hidden rounded-lg border">
      {/* Header */}
      <button
        className="flex w-full items-center gap-2 bg-muted/50 px-3 py-2 text-left hover:bg-muted/70"
        onClick={() => setIsExpanded(!isExpanded)}
      >
        {isExpanded ? (
          <ChevronDown className="h-4 w-4 shrink-0" />
        ) : (
          <ChevronRight className="h-4 w-4 shrink-0" />
        )}

        <Wrench className="h-4 w-4 shrink-0 text-muted-foreground" />

        <span className="flex-1 truncate font-medium text-sm">
          {toolUse.name}
        </span>

        <div className="flex items-center gap-2">
          {toolUse.duration && (
            <span className="flex items-center gap-1 text-muted-foreground text-xs">
              <Clock className="h-3 w-3" />
              {formatDuration(toolUse.duration)}
            </span>
          )}

          <Badge
            className={cn(
              "text-xs",
              toolUse.status === "running" && "animate-pulse"
            )}
            variant="outline"
          >
            <span
              className={cn(
                "mr-1.5 h-1.5 w-1.5 rounded-full",
                getStatusColor()
              )}
            />
            {toolUse.status}
          </Badge>
        </div>
      </button>

      {/* Expanded content */}
      {isExpanded && (
        <div className="space-y-2 border-t p-3">
          {/* Input */}
          {toolUse.input !== undefined && toolUse.input !== null && (
            <div>
              <h4 className="mb-1 font-medium text-muted-foreground text-xs">
                Input
              </h4>
              <CodeBlock
                code={
                  typeof toolUse.input === "string"
                    ? toolUse.input
                    : JSON.stringify(toolUse.input, null, 2)
                }
                language="json"
                showLineNumbers={false}
              />
            </div>
          )}

          {/* Output */}
          {toolUse.output !== undefined && toolUse.output !== null && (
            <div>
              <h4 className="mb-1 font-medium text-muted-foreground text-xs">
                Output
              </h4>
              <CodeBlock
                code={
                  typeof toolUse.output === "string"
                    ? toolUse.output
                    : JSON.stringify(toolUse.output, null, 2)
                }
                language={toolUse.status === "error" ? "text" : "json"}
                showLineNumbers={false}
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`;
  return `${Math.floor(ms / 60_000)}m ${Math.floor((ms % 60_000) / 1000)}s`;
}
