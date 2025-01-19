export default function FeedbackLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <section className="w-full px-4 py-6 ">
      <div className="max-w-4xl mx-auto flex flex-col">{children}</div>
    </section>
  );
}
