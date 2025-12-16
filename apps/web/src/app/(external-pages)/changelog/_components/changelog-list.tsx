import type { DBTable } from "@/types";
import { ChangelogEntry } from "./changelog-entry";

interface ChangelogListProps {
  changelogs: DBTable<"marketing_changelog">[];
}

export function ChangelogList({ changelogs }: ChangelogListProps) {
  if (changelogs.length === 0) {
    return (
      <div className="flex h-48 items-center justify-center rounded-lg border border-dashed">
        <p className="text-muted-foreground">No changelog entries yet.</p>
      </div>
    );
  }

  return (
    <div className="relative space-y-12 md:space-y-16">
      {/* Timeline line - visible on md+ */}
      <div className="absolute top-0 left-[139px] hidden h-full w-px bg-border md:block" />

      {changelogs.map((entry) => (
        <div className="relative" key={entry.id}>
          {/* Timeline dot - visible on md+ */}
          <div className="absolute top-1 left-[135px] hidden h-2.5 w-2.5 rounded-full border-2 border-background bg-muted-foreground md:block" />
          <ChangelogEntry entry={entry} />
        </div>
      ))}
    </div>
  );
}
