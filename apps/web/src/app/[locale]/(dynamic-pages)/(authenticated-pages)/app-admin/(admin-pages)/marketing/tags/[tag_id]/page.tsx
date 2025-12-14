import { notFound } from "next/navigation";
import { Suspense } from "react";
import { getMarketingTagById } from "@/data/admin/marketing-tags";
import { EditTagForm } from "./edit-tag-form";

async function EditTagPageContent(props: {
  params: Promise<{ tag_id: string }>;
}) {
  const params = await props.params;
  const tag = await getMarketingTagById(params.tag_id);

  if (!tag) {
    notFound();
  }

  return (
    <div className="space-y-6">
      <h1 className="font-bold text-3xl">Edit Tag</h1>
      <EditTagForm tag={tag} />
    </div>
  );
}

export default async function EditTagPage(props: {
  params: Promise<{ tag_id: string }>;
}) {
  return (
    <Suspense>
      <EditTagPageContent params={props.params} />
    </Suspense>
  );
}
