import { ensureAppAdmin } from '@/data/admin/security';
import { supabaseAdminClient } from '@/supabase-clients/admin/supabaseAdminClient';
import { NextRequest } from 'next/server';

export async function POST(request: NextRequest) {
  await ensureAppAdmin();
  const data = await request.formData();
  const body = Object.fromEntries(data);
  if ('file' in body && body.file instanceof File) {
    const { file } = body;

    const blogImagePath = `/assets/${file.name}`;

    const { data: uploadData, error } = await supabaseAdminClient.storage
      .from('admin-blog')
      .upload(blogImagePath, file, {
        upsert: false,
      });

    if (error) {
      console.log(error);
      throw new Error(error.message);
    }
    const { data } = supabaseAdminClient.storage
      .from('admin-blog')
      .getPublicUrl(uploadData.path);
    return new Response(JSON.stringify(data), { status: 200 });
  } else {
    throw new Error('No file was provided');
  }
}
