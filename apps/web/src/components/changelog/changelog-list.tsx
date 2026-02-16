import type { Tables } from "database/types";
import { TiptapJSONContentToHTML } from "@/components/tiptap-json-content-to-html";
import { formatChangelogDate, getTagColor } from "@/utils/changelog";

type ChangelogItem = Tables<"marketing_changelog">;

type ChangelogListProps = {
  items: ChangelogItem[];
};

export function ChangelogList({ items }: ChangelogListProps) {
  return (
    <div className="flex flex-col gap-6">
      {items.map((item) => (
        <article
          key={item.id}
          className="rounded-2xl border border-white/10 bg-white/5 p-6"
        >
          <div className="flex flex-wrap items-center gap-3 text-xs text-white/60">
            {item.created_at && (
              <span>{formatChangelogDate(item.created_at)}</span>
            )}
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
                <span
                  key={`${item.id}-${tag}`}
                  className={`rounded-full border px-2.5 py-1 text-xs ${getTagColor(
                    tag
                  )}`}
                >
                  {tag}
                </span>
              ))}
            </div>
          ) : null}
        </article>
      ))}
    </div>
  );
}
