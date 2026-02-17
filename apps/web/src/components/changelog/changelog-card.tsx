import type { Tables } from "database/types";
import { TiptapJSONContentToHTML } from "@/components/tiptap-json-content-to-html";
import { formatChangelogDate } from "@/utils/changelog";
import {
  ChangelogMedia,
  type ChangelogMediaType,
} from "./changelog-media";
import { ChangelogTagPill } from "./changelog-tag-pill";

type ChangelogItem = Tables<"marketing_changelog">;

type ChangelogCardProps = {
  item: ChangelogItem;
};

export function ChangelogCard({ item }: ChangelogCardProps) {
  const mediaSource = item.media_url ?? item.cover_image ?? null;
  const mediaType = resolveMediaType(
    item.media_type,
    mediaSource,
    Boolean(item.cover_image)
  );

  return (
    <article className="rounded-2xl border border-white/10 bg-white/5 p-6">
      {mediaSource && mediaType ? (
        <div className="mb-5 overflow-hidden rounded-xl border border-white/10 bg-black/40">
          <ChangelogMedia
            type={mediaType}
            src={mediaSource}
            alt={item.media_alt ?? item.title}
            poster={item.media_poster}
            className="h-auto w-full"
          />
        </div>
      ) : null}

      <div className="flex flex-wrap items-center gap-3 text-xs text-white/60">
        {item.created_at && <span>{formatChangelogDate(item.created_at)}</span>}
        {item.version && (
          <span className="rounded-full border border-white/10 px-2 py-0.5 text-white/70">
            {item.version}
          </span>
        )}
      </div>

      <h2 className="mt-3 text-xl text-white">{item.title}</h2>

      {item.json_content ? (
        <div className="prose prose-invert mt-4 line-clamp-4 max-w-none text-sm text-white/70">
          <TiptapJSONContentToHTML jsonContent={item.json_content} />
        </div>
      ) : null}

      {item.technical_details ? (
        <div className="mt-4 whitespace-pre-wrap rounded-xl border border-white/10 bg-black/40 px-4 py-3 font-mono text-xs text-white/70">
          {item.technical_details}
        </div>
      ) : null}

      {item.tags?.length ? (
        <div className="mt-4 flex flex-wrap gap-2">
          {item.tags.map((tag) => (
            <ChangelogTagPill key={`${item.id}-${tag}`} tag={tag} />
          ))}
        </div>
      ) : null}
    </article>
  );
}

function inferMediaType(
  mediaSource: string | null,
  isCoverImage: boolean
): ChangelogMediaType | null {
  if (!mediaSource) {
    return null;
  }
  const normalized = mediaSource.toLowerCase();
  if (normalized.endsWith(".gif")) {
    return "gif";
  }
  if (
    normalized.endsWith(".mp4") ||
    normalized.endsWith(".webm") ||
    normalized.endsWith(".mov")
  ) {
    return "video";
  }
  return isCoverImage ? "image" : "image";
}

function resolveMediaType(
  mediaType: string | null,
  mediaSource: string | null,
  isCoverImage: boolean
): ChangelogMediaType | null {
  if (isChangelogMediaType(mediaType)) {
    return mediaType;
  }

  return inferMediaType(mediaSource, isCoverImage);
}

function isChangelogMediaType(value: string | null): value is ChangelogMediaType {
  return value === "image" || value === "video" || value === "gif";
}
