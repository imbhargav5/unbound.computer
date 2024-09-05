import { getPage, getPages } from '@/app/source';
import { MDXContent } from '@content-collections/mdx/react';
import { TOCItemType } from 'fumadocs-core/server';
import { Accordion, Accordions } from 'fumadocs-ui/components/accordion';
import { Banner } from 'fumadocs-ui/components/banner';
import { Callout } from 'fumadocs-ui/components/callout';
import { CodeBlock, Pre } from 'fumadocs-ui/components/codeblock';
import { File, Files, Folder } from 'fumadocs-ui/components/files';
import { Tab, Tabs } from 'fumadocs-ui/components/tabs';
import defaultMdxComponents from 'fumadocs-ui/mdx';
import {
  DocsBody,
  DocsDescription,
  DocsPage,
  DocsTitle,
} from 'fumadocs-ui/page';
import type { Metadata } from 'next';
import dynamic from 'next/dynamic';
import { notFound } from 'next/navigation';

import { cn } from '@/utils/cn';
import type { HTMLAttributes } from 'react';

export function Wrapper(
  props: HTMLAttributes<HTMLDivElement>,
): React.ReactElement {
  return (
    <div
      {...props}
      className={cn(
        'rounded-xl bg-gradient-to-br from-pink-500 to-blue-500 p-4 prose-no-margin',
        props.className,
      )}
    >
      {props.children}
    </div>
  );
}

const ImageZoom = dynamic(() =>
  import('fumadocs-ui/components/image-zoom').then((m) => m.ImageZoom),
);

export default async function Page({
  params,
}: {
  params: { slug?: string[] };
}) {
  const page = getPage(params.slug);

  if (!page) {
    notFound();
  }
  return (
    <DocsPage toc={page.data.toc as TOCItemType[]} full={page.data.full}>
      <DocsTitle>{page.data.title}</DocsTitle>
      <DocsDescription>{page.data.description}</DocsDescription>
      <DocsBody>
        <MDXContent
          code={page.data.body}
          components={{
            ...defaultMdxComponents,
            Callout,
            Accordion,
            Accordions,
            File,
            Folder,
            Files,
            Banner,
            ImageZoom: (props) => <Wrapper>
              <ImageZoom {...props}
                src={props.src ?? `https://media.istockphoto.com/id/1409329028/vector/no-picture-available-placeholder-thumbnail-icon-illustration-design.jpg?s=612x612&w=0&k=20&c=_zOuJu755g2eEUioiOUdz_mHKJQJn-tDgIAhQzyeKUQ=`}
                alt={props.alt ?? ''}
                width={1200}
                height={630}
              />
            </Wrapper>,
            pre: ({ ref: _ref, ...props }) => (
              <CodeBlock {...props}>
                <Pre>{props.children}</Pre>
              </CodeBlock>
            ),
            Tab,
            Tabs,
          }}
        />
      </DocsBody>
    </DocsPage>
  );
}

export async function generateStaticParams() {
  return getPages().map((page) => ({
    slug: page.slugs,
  }));
}

export function generateMetadata({ params }: { params: { slug?: string[] } }) {
  const page = getPage(params.slug);

  if (!page) notFound();

  return {
    title: page.data.title,
    description: page.data.description,
  } satisfies Metadata;
}
