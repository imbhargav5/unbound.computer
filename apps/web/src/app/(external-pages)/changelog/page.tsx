import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Changelog | Unbound",
  description: "Product updates, releases, and improvements from Unbound.",
};

export default async function ChangelogPage() {
  return (
    <div className="mx-auto flex w-full max-w-5xl flex-col gap-4 px-6 py-16 lg:py-24">
      <h1 className="font-light text-4xl text-white">Changelog</h1>
      <p className="text-white/60">
        The Unbound changelog will list product updates here soon.
      </p>
    </div>
  );
}
