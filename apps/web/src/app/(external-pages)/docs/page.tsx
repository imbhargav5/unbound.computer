import { Suspense } from "react";
import { DocsClientContent } from "./docs-client-content";

async function DocsContent() {
  "use cache";
  return (
    <Suspense>
      <DocsClientContent />
    </Suspense>
  );
}

export default async function DocsPage() {
  return <DocsContent />;
}
