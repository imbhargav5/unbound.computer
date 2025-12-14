import { setRequestLocale } from "next-intl/server";
import { Suspense } from "react";
import { DocsClientContent } from "./docs-client-content";

const fadeIn = {
  initial: { opacity: 0, y: 20 },
  animate: { opacity: 1, y: 0 },
  transition: { duration: 0.5 },
};

async function DocsContent() {
  "use cache";
  return (
    <Suspense>
      <DocsClientContent />
    </Suspense>
  );
}

export default async function DocsPage(props: {
  params: Promise<{ locale: string }>;
}) {
  const params = await props.params;
  const { locale } = params;
  setRequestLocale(locale);
  return <DocsContent />;
}
