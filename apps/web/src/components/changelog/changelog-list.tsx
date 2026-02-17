import type { Tables } from "database/types";
import { ChangelogCard } from "@/components/changelog/changelog-card";

type ChangelogItem = Tables<"marketing_changelog">;

type ChangelogListProps = {
  items: ChangelogItem[];
};

export function ChangelogList({ items }: ChangelogListProps) {
  return (
    <div className="flex flex-col gap-6">
      {items.map((item) => (
        <ChangelogCard item={item} key={item.id} />
      ))}
    </div>
  );
}
