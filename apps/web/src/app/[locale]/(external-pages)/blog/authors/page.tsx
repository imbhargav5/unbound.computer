import { notFound } from "next/navigation";
import { setRequestLocale } from "next-intl/server";
import { Suspense } from "react";
import { T } from "@/components/ui/typography-ui";
import { cachedGetAllAuthors } from "@/data/anon/marketing-blog";
import AuthorCard from "../author-card";

export default async function BlogPostPage(props: {
  params: Promise<{ locale: string }>;
}) {
  "use cache: remote";
  const params = await props.params;

  const { locale } = params;

  setRequestLocale(locale);
  const authors = await cachedGetAllAuthors();
  try {
    return (
      <div className="w-full space-y-8">
        <div className="flex flex-col items-center space-y-4">
          <div className="mb-6 space-y-3 text-center">
            <T.Subtle>Contributions</T.Subtle>
            <T.H1>Authors</T.H1>
            <T.P className="text-muted-foreground text-xl leading-[30px]">
              Our blog is made possible because of contributions from these
              awesome folks!
            </T.P>
          </div>
        </div>
        <div className="flex flex-col gap-5">
          <Suspense fallback={<T.Subtle>Loading authors...</T.Subtle>}>
            {authors.map((author) => (
              <AuthorCard author={author} key={author.id} />
            ))}
          </Suspense>
        </div>
      </div>
    );
  } catch (error) {
    return notFound();
  }
}
