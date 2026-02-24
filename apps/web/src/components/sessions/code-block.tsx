"use client";

import { Check, Copy } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

interface CodeBlockProps {
  code: string;
  filename?: string;
  language?: string;
  showLineNumbers?: boolean;
}

export function CodeBlock({
  code,
  language = "text",
  filename,
  showLineNumbers = true,
}: CodeBlockProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(code);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const lines = code.split("\n");

  return (
    <div className="group relative overflow-hidden rounded-lg border bg-muted/50">
      {/* Header */}
      <div className="flex items-center justify-between border-b bg-muted/50 px-3 py-1.5">
        <span className="text-muted-foreground text-xs">
          {filename ?? language}
        </span>
        <Button
          className="h-6 opacity-0 transition-opacity group-hover:opacity-100"
          onClick={handleCopy}
          size="sm"
          variant="ghost"
        >
          {copied ? (
            <Check className="h-3 w-3" />
          ) : (
            <Copy className="h-3 w-3" />
          )}
        </Button>
      </div>

      {/* Code */}
      <div className="overflow-x-auto">
        <pre className="p-3 text-sm">
          <code>
            {lines.map((line, i) => (
              <div className="flex" key={i}>
                {showLineNumbers && (
                  <span
                    className={cn(
                      "mr-4 inline-block w-8 select-none text-right text-muted-foreground"
                    )}
                  >
                    {i + 1}
                  </span>
                )}
                <span>{line || " "}</span>
              </div>
            ))}
          </code>
        </pre>
      </div>
    </div>
  );
}
