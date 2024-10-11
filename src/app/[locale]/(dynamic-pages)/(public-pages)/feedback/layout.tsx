export default function FeedbackLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <section className="w-full h-screen max-h-screen px-4 py-6 ">
      <main className="max-w-[1296px] h-full max-h-[calc(100%-3rem)] mx-auto flex flex-col">
        {children}
      </main>
    </section>
  );
}
