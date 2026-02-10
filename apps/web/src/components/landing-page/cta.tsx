import { Terminal } from "lucide-react";
import { Button } from "@/components/ui/button";

export default function CTA() {
  return (
    <section className="relative px-6 py-24 lg:py-32">
      <div className="mx-auto max-w-3xl text-center">
        <div className="mb-6 inline-flex items-center justify-center rounded-full border border-white/10 p-4">
          <Terminal className="size-8 text-white" strokeWidth={1.5} />
        </div>

        <h2 className="mb-4 font-light text-3xl text-white lg:text-5xl">
          Ready to go unbound?
        </h2>

        <p className="mx-auto mb-8 max-w-xl text-lg text-white/40">
          We&apos;re building the future of remote Claude Code sessions.
        </p>

        <div className="flex flex-col justify-center gap-4 sm:flex-row">
          <Button
            className="cursor-default bg-white/10 px-8 py-6 text-base text-white hover:bg-white/10"
            disabled
          >
            Coming Soon
          </Button>
        </div>
      </div>
    </section>
  );
}
