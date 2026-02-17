import type { Metadata } from "next";
import { ChangelogList } from "@/components/changelog/changelog-list";
import { Link } from "@/components/intl-link";
import { cachedGetAllChangelogItems } from "@/data/anon/marketing-changelog";

export const metadata: Metadata = {
  title: "Changelog | Unbound",
  description: "Product updates, releases, and improvements from Unbound.",
};

export default async function ChangelogPage() {
  const changelogItems = await cachedGetAllChangelogItems();

  return (
    <div className="mx-auto flex w-full max-w-5xl flex-col gap-8 px-6 py-16 lg:py-24">
      <div className="flex flex-col gap-3">
        <h1 className="font-light text-4xl text-white">Changelog</h1>
        <p className="max-w-2xl text-white/60">
          Product releases, improvements, and updates from the Unbound team.
        </p>
      </div>

      {changelogItems.length === 0 ? (
        <div className="rounded-2xl border border-white/10 bg-white/5 px-8 py-10">
          <h2 className="text-lg text-white">
            No changelog entries published yet.
          </h2>
          <p className="mt-2 text-white/60">
            Check back soon or explore the docs to see what we’re building.
          </p>
          <Link className="mt-4 inline-flex text-sm text-white" href="/docs">
            Explore the docs
          </Link>
        </div>
      ) : (
        <ChangelogList items={changelogItems} />
      )}
    </div>
  );
}
