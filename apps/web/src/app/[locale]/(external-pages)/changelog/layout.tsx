import { setRequestLocale } from "next-intl/server";
import type React from "react";

type Props = { children: React.ReactNode; params: Promise<{ locale: string }> };

export default async function layout(props: Props) {
  const params = await props.params;

  const { locale } = params;

  const { children } = props;

  setRequestLocale(locale);
  return (
    <section className="w-full px-4 py-6">
      <div className="mx-auto flex h-full max-w-7xl flex-col">
        <div className="mt-4 h-full w-full">{children}</div>
      </div>
    </section>
  );
}
