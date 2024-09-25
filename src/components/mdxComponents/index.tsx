import { Link } from '@/components/intl-link';
import { cn } from '@/utils/cn';
import type { MDXComponents } from 'mdx/types';
import React, { HTMLAttributes } from 'react';
import { HashLink } from './/HashLink';

type TocNavProps = HTMLAttributes<HTMLElement>;

export const TocNav: React.FC<TocNavProps> = ({ children, ...props }) => {
  return (
    <nav
      aria-labelledby="on-this-page-title"
      {...props}
      className={cn('docs-toc-nav text-blue-500', 'w-56')}
    >
      <h2
        id="on-this-page-title"
        className="text-sm font-bold text-slate-900 dark:text-white"
      >
        On this page
      </h2>
      {children}
    </nav>
  );
};

// This file allows you to provide custom React components
// to be used in MDX files. You can import and use any
// React component you want, including components from
// other libraries.

export const customMDXComponents: MDXComponents = {
  a: ({ children, href, className, ref: _ref, ...props }) => {
    if (!href) {
      return (
        <a href={href} {...props}>
          {children}
        </a>
      );
    }
    const isTocLink = href.startsWith('#');
    if (isTocLink) {
      return (
        <HashLink href={href} {...props}>
          {children}
        </HashLink>
      );
    }
    return (
      <Link href={href} {...props}>
        {children}
      </Link>
    );
  },
  TocNav,
  prose: ({ as: Component = 'div', className, ...props }) => {
    return (
      <Component
        className={cn(
          className,
          'prose prose-neutral max-w-none dark:prose-invert',
          // headings
          'prose-headings:scroll-mt-28 prose-headings:font-display prose-headings:font-normal lg:prose-headings:scroll-mt-[8.5rem]',
          // lead
          'prose-lead:text-neutral-500 dark:prose-lead:text-neutral-400',
          // links
          'prose-a:font-semibold dark:prose-a:text-blue-400',
          // link underline
          'prose-a:no-underline prose-a:shadow-[inset_0_-2px_0_0_var(--tw-prose-background,#fff),inset_0_calc(-1*(var(--tw-prose-underline-size,4px)+2px))_0_0_var(--tw-prose-underline,theme(colors.blue.300))] hover:prose-a:[--tw-prose-underline-size:6px] dark:[--tw-prose-background:theme(colors.neutral.900)] dark:prose-a:shadow-[inset_0_calc(-1*var(--tw-prose-underline-size,2px))_0_0_var(--tw-prose-underline,theme(colors.blue.800))] dark:hover:prose-a:[--tw-prose-underline-size:6px]',
          // pre
          'prose-pre:rounded-xl prose-pre:bg-neutral-900 prose-pre:shadow-lg dark:prose-pre:bg-neutral-800/60 dark:prose-pre:shadow-none dark:prose-pre:ring-1 dark:prose-pre:ring-neutral-300/10',
          // hr
          'dark:prose-hr:border-neutral-800',
        )}
        {...props}
      />
    );
  },
  table: ({ className, ...props }) => {
    return (
      <div className="overflow-x-auto">
        <table
          className={cn(
            className,
            'table-auto w-full border-collapse border-gray-200 dark:border-gray-700',
          )}
          {...props}
        />
      </div>
    );
  },
  th: ({ className, ...props }) => {
    return (
      <th
        className={cn(
          className,
          'px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider',
        )}
        style={{ wordWrap: 'break-word' }} // Add this line
        {...props}
      />
    );
  },
  td: ({ className, ...props }) => {
    return (
      <td
        className={cn(
          className,
          'px-6 py-4 text-sm text-gray-900 dark:text-gray-100',
        )}
        style={{ wordWrap: 'break-word' }} // Add this line
        {...props}
      />
    );
  },
  tr: ({ className, ...props }) => {
    return (
      <tr
        className={cn(
          className,
          'border-t border-gray-200 dark:border-gray-700',
        )}
        {...props}
      />
    );
  },
  code: ({ className, ...props }) => {
    const languageClassExist = className
      ?.split(' ')
      ?.find((className) => className.indexOf('language') !== -1);
    // check if data-language prop exists
    const languageProp = Boolean(props['data-language']) || languageClassExist;
    return (
      <code
        className={cn(
          className,
          languageProp
            ? ''
            : 'p-1 border border-gray-700 dark:border-purple-600 dark:bg-transparent bg-purple-100',
        )}
        {...props}
      />
    );
  },
};

// This file is required to use MDX in `app` directory.
export function useMDXComponents(components: MDXComponents): MDXComponents {
  return {
    // Allows customizing built-in components, e.g. to add styling.
    // h1: ({ children }) => <h1 style={{ fontSize: "100px" }}>{children}</h1>,
    ...components,
    ...customMDXComponents,
  };
}
