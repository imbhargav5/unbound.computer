import { ArrowRight, Terminal } from "lucide-react";
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
        {/* Badge */}
        <div className="flex items-center gap-2 rounded-full border border-white/10 px-4 py-1.5">
          <div className="size-2 animate-pulse rounded-full bg-white" />
          <span className="text-sm text-white/70">End-to-End Encrypted</span>
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

        {/* CTAs */}
        <div className="flex flex-col gap-4 pt-4 sm:flex-row">
          <Button
            asChild
            className="bg-white px-8 py-6 text-base text-black hover:bg-white/90"
          >
            <Link href="/login">
              Get Started
              <ArrowRight className="ml-2" size={18} />
            </Link>
          </Button>
          <Button
            asChild
            className="border-white/20 bg-transparent px-8 py-6 text-base text-white hover:bg-white/5"
            variant="outline"
          >
            <Link href="/docs">
              <Terminal className="mr-2" size={18} />
              Documentation
            </Link>
          </Button>
        </div>
      </div>
    </section>
  );
}
