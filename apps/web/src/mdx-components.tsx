import defaultMdxComponents from "fumadocs-ui/mdx";
import type { MDXComponents } from "mdx/types";
import type { ElementType } from "react";

const cn = (...classes: Array<string | false | null | undefined>) =>
  classes.filter(Boolean).join(" ");

const withClassName = (Component: ElementType, baseClassName: string) => {
  const Wrapped = ({
    className,
    ...props
  }: {
    className?: string;
    [key: string]: unknown;
  }) => <Component className={cn(baseClassName, className)} {...props} />;

  return Wrapped;
};

export function getMDXComponents(components?: MDXComponents): MDXComponents {
  const merged = {
    ...defaultMdxComponents,
    ...components,
  } as Record<string, ElementType | undefined>;

  return {
    ...merged,
    h1: withClassName(
      merged.h1 ?? "h1",
      "mt-10 scroll-m-20 font-light text-4xl text-white tracking-tight"
    ),
    h2: withClassName(
      merged.h2 ?? "h2",
      "mt-8 scroll-m-20 font-light text-2xl text-white tracking-tight"
    ),
    h3: withClassName(
      merged.h3 ?? "h3",
      "mt-6 scroll-m-20 font-medium text-white text-xl"
    ),
    h4: withClassName(
      merged.h4 ?? "h4",
      "mt-4 scroll-m-20 font-medium text-lg text-white/90"
    ),
    p: withClassName(
      merged.p ?? "p",
      "mt-4 text-base text-white/70 leading-relaxed"
    ),
    a: withClassName(
      merged.a ?? "a",
      "font-medium text-white/80 underline underline-offset-4 decoration-white/30 transition-colors hover:text-white hover:decoration-white/60"
    ),
    ul: withClassName(
      merged.ul ?? "ul",
      "mt-4 list-disc space-y-2 pl-6 text-white/70"
    ),
    ol: withClassName(
      merged.ol ?? "ol",
      "mt-4 list-decimal space-y-2 pl-6 text-white/70"
    ),
    li: withClassName(merged.li ?? "li", "leading-relaxed"),
    blockquote: withClassName(
      merged.blockquote ?? "blockquote",
      "mt-6 border-white/20 border-l-2 pl-4 text-white/70 italic"
    ),
    code: withClassName(
      merged.code ?? "code",
      "rounded bg-white/10 px-1.5 py-0.5 font-mono text-[0.9em] text-white"
    ),
    pre: withClassName(
      merged.pre ?? "pre",
      "mt-6 overflow-x-auto rounded-2xl border border-white/10 bg-white/[0.04] p-4 text-sm text-white/80"
    ),
    hr: withClassName(merged.hr ?? "hr", "my-10 border-white/10"),
  };
}
