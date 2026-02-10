import { Github } from "lucide-react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";

export default async function HeroSection() {
  return (
    <section className="relative mx-auto max-w-5xl px-6 py-20 text-center lg:py-32">
      {/* Subtle radial gradient glow behind headline */}
      <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
        <div className="h-[500px] w-[800px] rounded-full bg-white/[0.02] blur-3xl" />
      </div>

      <div className="relative flex w-full flex-col items-center gap-8">
        {/* Badges */}
        <div className="flex flex-wrap items-center justify-center gap-3">
          <div className="flex items-center gap-2 rounded-full border border-white/10 px-4 py-1.5">
            <div className="size-2 animate-pulse rounded-full bg-white" />
            <span className="text-sm text-white/70">End-to-End Encrypted</span>
          </div>
          <div className="flex items-center gap-2 rounded-full border border-white/10 px-4 py-1.5">
            <Github className="size-3.5 text-white/70" />
            <span className="text-sm text-white/70">Open Source</span>
          </div>
        </div>

        {/* Headline */}
        <h1 className="max-w-4xl font-light text-4xl text-white tracking-tight sm:text-5xl lg:text-7xl">
          Run Claude Code
          <br />
          <span className="text-white/50">from anywhere</span>
        </h1>

        {/* Subheadline */}
        <p className="max-w-2xl text-lg text-white/40 leading-relaxed lg:text-xl">
          Control Claude Code sessions on your Mac from your phone.
          Zero-knowledge encryption ensures your code never leaves your trusted
          devices.
        </p>

        {/* CTAs — hidden for now */}
        <div className="hidden flex-col gap-4 pt-4 sm:hidden">
          <Button
            asChild
            className="bg-white px-8 py-6 text-base text-black hover:bg-white/90"
          >
            <Link href="/login">Get Started</Link>
          </Button>
        </div>
      </div>
    </section>
  );
}
