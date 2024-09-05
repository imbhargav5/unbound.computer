import { Badge } from '@/components/ui/badge';
import { Separator } from '@/components/ui/separator';
import type { Tables } from '@/lib/database.types';

import { formatDistance } from 'date-fns';
import { CalendarDaysIcon } from 'lucide-react';
import Markdown from 'markdown-to-jsx';
import Image from 'next/image';
type Props = {
  changelogs: Tables<'internal_changelog'>[];
};

export const ChangelogPosts = ({ changelogs }: Props) => {
  return (
    <>
      {changelogs.map((changelog, index) => (
        <div
          key={changelog.id}
          className="grid-cols-5 grid gap-4 mx-auto md:p-8 max-w-5xl"
        >
          <div className="flex flex-col mb-8 col-span-1 gap-2">
            <div className="md:flex items-center">
              <CalendarDaysIcon className="text-muted-foreground mr-2" />
              <span className="text-sm text-muted-foreground w-fit">
                {formatDistance(
                  new Date(changelog.created_at as string),
                  new Date(),
                  {
                    addSuffix: true,
                  },
                )}
              </span>
            </div>
            {index === 0 && <Badge className="mr-2 p-2 px-4 w-fit">NEW</Badge>}
          </div>
          <div className="mb-8 space-y-4 col-span-4">
            <div className="relative h-64">
              <Image
                alt="Changelog image"
                fill
                className="mb-4 object-cover h-64 rounded-lg"
                src={changelog.cover_image ?? ''}
              />
            </div>
            <h1 className="text-2xl font-bold">{changelog.title}</h1>
            <div className="p-4 max-w-screen-lg">
              <Markdown
                options={{
                  overrides: {
                    h1: {
                      component: 'h1',
                      props: {
                        className:
                          'prose max-w-screen-lg break-words dark:prose-invert dark:text-foreground prose-headings:scroll-mt-28 prose-headings:font-display prose-headings:font-normal lg:prose-headings:scroll-mt-[8.5rem]',
                      },
                    },
                    h2: {
                      component: 'h2',
                      props: {
                        className:
                          'prose max-w-screen-lg break-words dark:prose-invert dark:text-foreground prose-headings:scroll-mt-28 prose-headings:font-display prose-headings:font-normal lg:prose-headings:scroll-mt-[8.5rem]',
                      },
                    },
                    h3: {
                      component: 'h3',
                      props: {
                        className:
                          'prose max-w-screen-lg break-words dark:prose-invert dark:text-foreground prose-headings:scroll-mt-28 prose-headings:font-display prose-headings:font-normal lg:prose-headings:scroll-mt-[8.5rem]',
                      },
                    },
                    h4: {
                      component: 'h4',
                      props: {
                        className:
                          'prose max-w-screen-lg break-words dark:prose-invert dark:text-foreground prose-headings:scroll-mt-28 prose-headings:font-display prose-headings:font-normal lg:prose-headings:scroll-mt-[8.5rem]',
                      },
                    },
                    h5: {
                      component: 'h5',
                      props: {
                        className:
                          'prose max-w-screen-lg break-words dark:prose-invert dark:text-foreground prose-headings:scroll-mt-28 prose-headings:font-display prose-headings:font-normal lg:prose-headings:scroll-mt-[8.5rem]',
                      },
                    },
                    h6: {
                      component: 'h6',
                      props: {
                        className:
                          'prose max-w-screen-lg break-words dark:prose-invert dark:text-foreground prose-headings:scroll-mt-28 prose-headings:font-display prose-headings:font-normal lg:prose-headings:scroll-mt-[8.5rem]',
                      },
                    },
                    p: {
                      component: 'p',
                      props: {
                        className:
                          'prose max-w-screen-lg break-words dark:prose-invert dark:text-foreground',
                      },
                    },
                    a: {
                      component: 'a',
                      props: {
                        className:
                          'prose max-w-screen-lg break-words dark:prose-invert dark:text-foreground prose-a:font-semibold dark:prose-a:text-sky-400 prose-a:no-underline hover:prose-a:[--tw-prose-underline-size:6px]',
                      },
                    },
                    ul: {
                      component: 'ul',
                      props: {
                        className:
                          'list-disc prose max-w-screen-lg break-words dark:prose-invert dark:text-foreground',
                      },
                    },
                    ol: {
                      component: 'ol',
                      props: {
                        className:
                          'prose max-w-screen-lg break-words dark:prose-invert dark:text-foreground',
                      },
                    },
                    li: {
                      component: 'li',
                      props: { className: 'ml-8' }, // Adjust classes as needed
                    },
                    pre: {
                      component: 'pre',
                      props: {
                        className:
                          'prose-pre:rounded-xl prose-pre:bg-background prose-pre:shadow-lg dark:prose-pre:bg-background dark:prose-pre:shadow-none dark:prose-pre:ring-1 dark:prose-pre:ring-foreground',
                      },
                    },
                    code: {
                      component: 'code',
                      props: {
                        className:
                          'prose max-w-screen-lg break-words dark:prose-invert dark:text-foreground',
                      },
                    },
                    hr: {
                      component: 'hr',
                      props: { className: 'dark:prose-hr:border-neutral-800' },
                    },
                    img: {
                      component: 'img',
                      props: {
                        className: 'h-64 max-w-screen-lg break-words',
                      },
                    },
                  },
                }}
              >
                {changelog.changes}
              </Markdown>
            </div>
            <Separator />
          </div>
        </div>
      ))}
    </>
  );
};
