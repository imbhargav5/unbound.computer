import type React from 'react';

type Props = { children: React.ReactNode };

export default function layout({ children }: Props) {
  return (
    <section className="w-full px-4 py-6 ">
      <main className="max-w-7xl h-full mx-auto flex flex-col">
        <div className="mt-4 w-full h-full">{children}</div>
      </main>
    </section>
  );
}
