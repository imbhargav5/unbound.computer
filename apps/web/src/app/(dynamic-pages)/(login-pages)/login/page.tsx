import type { Metadata } from "next";
import { Suspense } from "react";
import { z } from "zod";
import { Login } from "./login";

const SearchParamsSchema = z.object({
  next: z.string().optional(),
  nextActionType: z.string().optional(),
});

export const metadata: Metadata = {
  title: "Login | Nextbase Starter Kits Demo",
  description: "Login to your Nextbase Starter Kits Demo account",
};

async function LoginPageContent({
  searchParams,
}: {
  searchParams: Promise<unknown>;
}) {
  const searchParamsValue = await searchParams;
  const validatedSearchParams = SearchParamsSchema.parse(searchParamsValue);
  return (
    <Login
      next={validatedSearchParams.next}
      nextActionType={validatedSearchParams.nextActionType}
    />
  );
}

export default async function LoginPage(props: {
  searchParams: Promise<unknown>;
}) {
  return (
    <Suspense>
      <LoginPageContent searchParams={props.searchParams} />
    </Suspense>
  );
}
