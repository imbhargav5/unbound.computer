import { getTagById } from '@/data/admin/marketing-tags';
import { notFound } from 'next/navigation';
import { EditTagForm } from './EditTagForm';

export default async function EditTagPage({ params }: { params: { tag_id: string } }) {
  const tag = await getTagById(params.tag_id);

  if (!tag) {
    notFound();
  }

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">Edit Tag</h1>
      <EditTagForm tag={tag} />
    </div>
  );
}
