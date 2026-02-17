import { DocsLayout } from "fumadocs-ui/layouts/docs";
import { baseOptions } from "@/app/layout.config";
import { source } from "../source";
import "@/styles/docs-layout-styles.css";
import { RootProvider } from "fumadocs-ui/provider/next";
import { ExternalNavigation } from "@/components/navigation-menu/external-navbar/external-navigation";
import { Footer } from "@/components/landing-page/footer";

export default async function Layout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="dark flex min-h-screen flex-col bg-black text-white">
      <ExternalNavigation />
      <div className="flex-1">
        <div className="mx-auto w-full max-w-6xl px-6 pt-16 md:px-8">
          <RootProvider>
            <DocsLayout tree={source.pageTree} {...baseOptions()}>
              {children}
            </DocsLayout>
          </RootProvider>
        </div>
      </div>
      <Footer />
    </div>
  );
}
