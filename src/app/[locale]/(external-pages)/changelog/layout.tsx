import { unstable_setRequestLocale } from "next-intl/server";
import type React from "react";

type Props = { children: React.ReactNode; params: { locale: string } };

export default function layout({ children, params: { locale } }: Props) {
  unstable_setRequestLocale(locale);
  return (
    <section className="w-full px-4 py-6 ">
      <main className="max-w-7xl h-full mx-auto flex flex-col">
        <div className="mt-4 w-full h-full">{children}</div>
      </main>
    </section>
  );
}
