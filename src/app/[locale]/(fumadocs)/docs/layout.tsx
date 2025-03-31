import { pageTree } from "@/app/[locale]/source";
import { baseOptions } from "@/app/layout.config";
import "@/styles/docs-layout-styles.css";
import { RootToggle } from "fumadocs-ui/components/layout/root-toggle";
import { DocsLayout } from "fumadocs-ui/layouts/docs";
import { Home } from "lucide-react";
import type { ReactNode } from "react";

export default function RootDocsLayout({ children }: { children: ReactNode }) {
  return (
    <DocsLayout
      tree={pageTree}
      sidebar={{
        banner: (
          <RootToggle
            options={[
              {
                title: "Page Tree 1",
                description: "Pages in page tree 1",
                url: "/docs/page-tree-1",
                icon: <Home />,
              },
              {
                title: "Page Tree 2",
                description: "Pages in page tree 2",
                url: "/docs/page-tree-2",
                icon: <Home />,
              },
            ]}
          />
        ),
      }}
      links={[
        {
          text: "Home",
          url: "/",
        },
        {
          text: "Blog",
          url: "/blog",
          active: "none",
        },
      ]}
      {...baseOptions}
    >
      {children}
    </DocsLayout>
  );
}
