import type React from "react";

type Props = { children: React.ReactNode };

export default async function layout({ children }: Props) {
  return (
    <section className="w-full px-4 py-6">
      <div className="mx-auto flex h-full max-w-7xl flex-col">
        <div className="mt-4 h-full w-full">{children}</div>
      </div>
    </section>
  );
}
