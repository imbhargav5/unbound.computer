export default function Quotation() {
  return (
    <section className="relative px-6 py-24 lg:py-32">
      {/* Decorative lines */}
      <div className="mx-auto mb-12 h-px w-16 bg-white/20" />

      <h2 className="mx-auto max-w-4xl text-center font-light text-2xl text-white leading-relaxed lg:text-4xl lg:leading-relaxed">
        Start Claude Code from your couch, review diffs on the train, merge PRs
        from anywhere.{" "}
        <span className="text-white/40">
          Your dev machine stays secure at home.
        </span>
      </h2>

      <div className="mx-auto mt-12 h-px w-16 bg-white/20" />
    </section>
  );
}
