import { unstable_setRequestLocale } from "next-intl/server";
import type React from "react";

type Props = { children: React.ReactNode; params: Promise<{ locale: string }> };

export default async function layout(props: Props) {
  const params = await props.params;

  const { locale } = params;

  const { children } = props;

  unstable_setRequestLocale(locale);
  return (
    <section className="w-full px-4 py-6 ">
      <div className="max-w-7xl h-full mx-auto flex flex-col">
        <div className="mt-4 w-full h-full">{children}</div>
      </div>
    </section>
  );
}
