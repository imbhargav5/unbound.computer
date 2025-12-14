import { format } from "date-fns";

// Predefined tag options for changelog entries
export const TAG_OPTIONS = [
  "New Feature",
  "AI",
  "UI",
  "Improvement",
  "Collaboration",
  "Search",
  "Productivity",
  "API",
  "Integrations",
  "Bug Fix",
  "Performance",
  "Security",
] as const;

export type ChangelogTag = (typeof TAG_OPTIONS)[number];

// Semantic colors for changelog tags
export const tagColors: Record<string, string> = {
  "New Feature": "bg-emerald-500/10 text-emerald-600 border-emerald-500/20",
  AI: "bg-violet-500/10 text-violet-600 border-violet-500/20",
  UI: "bg-sky-500/10 text-sky-600 border-sky-500/20",
  Improvement: "bg-amber-500/10 text-amber-600 border-amber-500/20",
  Collaboration: "bg-pink-500/10 text-pink-600 border-pink-500/20",
  Search: "bg-indigo-500/10 text-indigo-600 border-indigo-500/20",
  Productivity: "bg-teal-500/10 text-teal-600 border-teal-500/20",
  API: "bg-orange-500/10 text-orange-600 border-orange-500/20",
  Integrations: "bg-cyan-500/10 text-cyan-600 border-cyan-500/20",
  "Bug Fix": "bg-red-500/10 text-red-600 border-red-500/20",
  Performance: "bg-lime-500/10 text-lime-600 border-lime-500/20",
  Security: "bg-rose-500/10 text-rose-600 border-rose-500/20",
};

// Get tag color class, with fallback for custom tags
export function getTagColor(tag: string): string {
  return tagColors[tag] || "bg-muted text-muted-foreground";
}

// Format date for changelog display (e.g., "Jan 15, 2025")
export function formatChangelogDate(date: string | Date): string {
  return format(new Date(date), "MMM d, yyyy");
}

// Media type for changelog featured media
export type ChangelogMediaType = "image" | "video" | "gif";

// Get accept string for file input based on media types
export function getMediaAcceptString(): string {
  return "image/jpeg,image/png,image/webp,image/gif,video/mp4,video/webm,video/quicktime";
}

// Check if a file is a valid media type
export function isValidMediaFile(file: File): boolean {
  const validTypes = [
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/gif",
    "video/mp4",
    "video/webm",
    "video/quicktime",
  ];
  return validTypes.includes(file.type.toLowerCase());
}

// Get media type from file
export function getMediaTypeFromFile(file: File): ChangelogMediaType {
  const mimeType = file.type.toLowerCase();

  if (mimeType === "image/gif") {
    return "gif";
  }
  if (mimeType.startsWith("video/")) {
    return "video";
  }
  return "image";
}
