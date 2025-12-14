"use client";

import { Code } from "lucide-react";
import { TiptapJSONContentToHTML } from "@/components/tiptap-json-content-to-html";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { Badge } from "@/components/ui/badge";
import type { DBTable } from "@/types";
import {
  type ChangelogMediaType,
  formatChangelogDate,
  getTagColor,
} from "@/utils/changelog";
import { ChangelogMedia } from "./changelog-media";

interface ChangelogEntryProps {
  entry: DBTable<"marketing_changelog">;
}

export function ChangelogEntry({ entry }: ChangelogEntryProps) {
  const tags = entry.tags ?? [];
  const mediaType = entry.media_type as ChangelogMediaType | null;

  return (
    <article className="relative grid gap-6 md:grid-cols-[140px_1fr] md:gap-10">
      {/* Date column - visible on md+ */}
      <div className="hidden md:block">
        <div className="-mt-2 sticky top-20 pt-2">
          <div className="rounded-md bg-background pb-2">
            {entry.created_at && (
              <time className="font-medium text-muted-foreground text-sm">
                {formatChangelogDate(entry.created_at)}
              </time>
            )}
            {entry.version && (
              <div className="mt-2">
                <Badge className="font-mono text-xs" variant="outline">
                  {entry.version}
                </Badge>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Main content */}
      <div className="space-y-4">
        {/* Mobile date/version */}
        <div className="flex items-center gap-3 md:hidden">
          {entry.version && (
            <Badge className="font-mono text-xs" variant="outline">
              {entry.version}
            </Badge>
          )}
          {entry.created_at && (
            <time className="text-muted-foreground text-sm">
              {formatChangelogDate(entry.created_at)}
            </time>
          )}
        </div>

        {/* Tags */}
        {tags.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {tags.map((tag) => (
              <Badge className={getTagColor(tag)} key={tag} variant="outline">
                {tag}
              </Badge>
            ))}
          </div>
        )}

        {/* Title */}
        <h2 className="font-semibold text-foreground text-xl tracking-tight md:text-2xl">
          {entry.title}
        </h2>

        {/* Media */}
        {mediaType && entry.media_url && (
          <div className="mt-4">
            <ChangelogMedia
              alt={entry.media_alt || undefined}
              posterUrl={entry.media_poster}
              type={mediaType}
              url={entry.media_url}
            />
          </div>
        )}

        {/* Description */}
        <div className="prose-sm text-muted-foreground">
          <TiptapJSONContentToHTML jsonContent={entry.json_content} />
        </div>

        {/* Technical Details Accordion */}
        {entry.technical_details && (
          <Accordion className="mt-4" collapsible type="single">
            <AccordionItem className="rounded-lg border px-4" value="technical">
              <AccordionTrigger className="font-medium text-sm hover:no-underline">
                <span className="flex items-center gap-2">
                  <Code className="h-4 w-4" />
                  Technical Details
                </span>
              </AccordionTrigger>
              <AccordionContent>
                <div className="prose-sm whitespace-pre-wrap pb-2 text-muted-foreground">
                  {entry.technical_details}
                </div>
              </AccordionContent>
            </AccordionItem>
          </Accordion>
        )}
      </div>
    </article>
  );
}
