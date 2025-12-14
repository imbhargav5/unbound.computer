import { notFound } from "next/navigation";
import { Suspense } from "react";
import { z } from "zod";
import { getAllAuthorProfiles } from "@/data/admin/marketing-authors";
import { getChangelogById } from "@/data/admin/marketing-changelog";
import { EditChangelogForm } from "./edit-changelog-form";

const editChangelogPageSchema = z.object({
  changelogId: z.uuid(),
});

async function EditChangelogPageContent(props: { params: Promise<unknown> }) {
  const params = await props.params;
  const { changelogId } = editChangelogPageSchema.parse(params);
  const changelog = await getChangelogById(changelogId);
  const authors = await getAllAuthorProfiles();

  if (!changelog) {
    notFound();
  }

  return (
    <div className="space-y-6">
      <h1 className="font-bold text-3xl">Edit Changelog</h1>
      <EditChangelogForm authors={authors} changelog={changelog} />
    </div>
  );
}

export default async function EditChangelogPage(props: {
  params: Promise<unknown>;
}) {
  return (
    <Suspense>
      <EditChangelogPageContent params={props.params} />
    </Suspense>
  );
}
