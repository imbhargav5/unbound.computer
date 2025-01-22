export default function FeedbackLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <section className="w-full h-full overflow-auto">{children}</section>;
}
