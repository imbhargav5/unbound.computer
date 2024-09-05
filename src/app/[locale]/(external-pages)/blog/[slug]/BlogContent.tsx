'use client';

import { getTipTapExtention } from '@/components/tip-tap-Editor/extensions';
import type { DBTable } from '@/types';
import { generateHTML } from '@tiptap/core';

export function BlogContent({
  jsonContent,
}: {
  jsonContent: DBTable<'internal_blog_posts'>['json_content'];
}) {
  const validContent =
    typeof jsonContent === 'string'
      ? JSON.parse(jsonContent)
      : typeof jsonContent === 'object' && jsonContent !== null
        ? jsonContent
        : {};
  return (
    <div
      dangerouslySetInnerHTML={{
        __html: generateHTML(
          validContent,
          getTipTapExtention({ placeholder: 'Write your blog post...' }),
        ),
      }}
    />
  );
}
