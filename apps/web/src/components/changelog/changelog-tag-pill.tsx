import { getTagColor } from "@/utils/changelog";
import { cn } from "@/utils/cn";

type ChangelogTagPillProps = {
  tag: string;
  className?: string;
};

export function ChangelogTagPill({ tag, className }: ChangelogTagPillProps) {
  return (
    <span
      className={cn(
        "rounded-full border px-2.5 py-1 text-xs",
        getTagColor(tag),
        className
      )}
    >
      {tag}
    </span>
  );
}
