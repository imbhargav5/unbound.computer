import type { Metadata } from "next";
import { Suspense } from "react";
import { z } from "zod";
import { SignUp } from "./sign-up";

const SearchParamsSchema = z.object({
  next: z.string().optional(),
  nextActionType: z.string().optional(),
});

export const metadata: Metadata = {
  title: "Sign Up | Unbound",
  description: "Create an account to get started with Unbound",
};

async function SignUpPageContent({
  searchParams,
}: {
  searchParams: Promise<unknown>;
}) {
  const searchParamsValue = await searchParams;
  const validatedSearchParams = SearchParamsSchema.parse(searchParamsValue);
  return (
    <SignUp
      next={validatedSearchParams.next}
      nextActionType={validatedSearchParams.nextActionType}
    />
  );
}

export default async function SignUpPage(props: {
  searchParams: Promise<unknown>;
}) {
  return (
    <Suspense>
      <SignUpPageContent searchParams={props.searchParams} />
    </Suspense>
  );
}
