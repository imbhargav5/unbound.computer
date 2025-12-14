import { ArrowLeft, Rss } from "lucide-react";
import { setRequestLocale } from "next-intl/server";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import { cachedGetAllChangelogItems } from "@/data/anon/marketing-changelog";
import { ChangelogList } from "./_components/changelog-list";

const isDev = process.env.NODE_ENV !== "production";

type ChangelogItems = Awaited<ReturnType<typeof cachedGetAllChangelogItems>>;

function handleSupabaseError<T>(
  error: unknown,
  fallback: T,
  context: string
): T {
  if (isDev) {
    console.warn(`[changelog] ${context} failed, falling back.`, error);
  }

  return fallback;
}

async function fetchChangelogItems(): Promise<ChangelogItems> {
  try {
    return await cachedGetAllChangelogItems();
  } catch (error) {
    return handleSupabaseError(error, [], "cachedGetAllChangelogItems");
  }
}

export default async function Page(props: {
  params: Promise<{ locale: string }>;
}) {
  "use cache: remote";
  const params = await props.params;

  const { locale } = params;

  setRequestLocale(locale);
  const changelogs = await fetchChangelogItems();

  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="border-border border-b">
        <div className="mx-auto max-w-4xl px-6 py-4">
          <Link
            className="inline-flex items-center gap-2 text-muted-foreground text-sm transition-colors hover:text-foreground"
            href="/feedback"
          >
            <ArrowLeft className="h-4 w-4" />
            Back to feedback
          </Link>
        </div>
      </header>

      {/* Hero */}
      <section className="border-border border-b bg-muted/30">
        <div className="mx-auto max-w-4xl px-6 py-12 md:py-16">
          <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
            <div>
              <h1
                className="font-bold text-3xl text-foreground tracking-tight md:text-4xl"
                data-testid="page-heading-title"
              >
                Changelog
              </h1>
              <p className="mt-2 text-muted-foreground">
                New updates and improvements to the platform.
              </p>
            </div>
            <Button
              className="w-fit gap-2 bg-transparent"
              size="sm"
              variant="outline"
            >
              <Rss className="h-4 w-4" />
              Subscribe to updates
            </Button>
          </div>
        </div>
      </section>

      {/* Changelog entries */}
      <main className="mx-auto max-w-4xl px-6 py-12 md:py-16">
        <ChangelogList changelogs={changelogs} />
      </main>
    </div>
  );
}
