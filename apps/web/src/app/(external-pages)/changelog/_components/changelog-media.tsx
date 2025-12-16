"use client";

import { Play } from "lucide-react";
import Image from "next/image";
import { useState } from "react";
import type { ChangelogMediaType } from "@/utils/changelog";

interface ChangelogMediaProps {
  type: ChangelogMediaType;
  url: string;
  alt?: string;
  posterUrl?: string | null;
}

export function ChangelogMedia({
  type,
  url,
  alt,
  posterUrl,
}: ChangelogMediaProps) {
  const [isPlaying, setIsPlaying] = useState(false);

  if (type === "video") {
    return (
      <div className="relative aspect-video w-full overflow-hidden rounded-lg border border-border bg-muted">
        {isPlaying ? (
          // biome-ignore lint/a11y/useMediaCaption: Changelog videos are visual demos without audio narration
          <video
            autoPlay
            className="h-full w-full object-cover"
            controls
            poster={posterUrl || undefined}
            src={url}
          />
        ) : (
          <button
            className="group absolute inset-0 flex items-center justify-center"
            onClick={() => setIsPlaying(true)}
            type="button"
          >
            {posterUrl ? (
              <Image
                alt={alt || "Video poster"}
                className="object-cover"
                fill
                sizes="(max-width: 768px) 100vw, 50vw"
                src={posterUrl}
                unoptimized
              />
            ) : (
              <div className="absolute inset-0 bg-muted" />
            )}
            <div className="absolute inset-0 bg-black/20 transition-colors group-hover:bg-black/30" />
            <div className="absolute flex h-16 w-16 items-center justify-center rounded-full bg-white/90 shadow-lg transition-transform group-hover:scale-110">
              <Play
                className="ml-1 h-7 w-7 text-foreground"
                fill="currentColor"
              />
            </div>
          </button>
        )}
      </div>
    );
  }

  if (type === "gif") {
    return (
      <div className="relative aspect-video w-full overflow-hidden rounded-lg border border-border bg-muted">
        <Image
          alt={alt || "Animated preview"}
          className="object-cover"
          fill
          src={url}
          unoptimized
        />
        <div className="absolute bottom-3 left-3 rounded-md bg-black/70 px-2 py-1 font-medium text-white text-xs">
          GIF
        </div>
      </div>
    );
  }

  // Default: image
  return (
    <div className="relative aspect-video w-full overflow-hidden rounded-lg border border-border bg-muted">
      <Image
        alt={alt || "Feature preview"}
        className="object-cover"
        fill
        src={url}
      />
    </div>
  );
}
