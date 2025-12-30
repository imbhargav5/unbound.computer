import { ArrowRight, Lock, Smartphone, Terminal } from "lucide-react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";

export default async function HeroSection() {
  return (
    <section className="mx-auto max-w-5xl px-6 py-10 text-left lg:py-20 lg:text-center">
      <div className="flex w-full flex-col gap-10">
        <div className="flex flex-1 flex-col space-y-4 lg:items-center">
          <div className="flex w-fit items-center gap-2 rounded-full border border-border bg-secondary px-3 py-1 dark:border-none">
            <Lock size={16} />
            <span className="font-medium text-md lg:text-base">
              End-to-End Encrypted
            </span>
          </div>
          <h1 className="max-w-2xl font-thin text-3xl lg:text-5xl">
            Run Claude Code on your machine <br />
            <em>from anywhere</em>
          </h1>
          <p className="max-w-4xl text-muted-foreground leading-loose lg:text-lg lg:leading-relaxed">
            Control Claude Code sessions on your Mac, Linux, or Windows machine
            from your phone. Secure relay infrastructure with zero-knowledge
            encryption ensures your code never leaves your trusted devices.
          </p>
          <div className="flex w-full flex-col gap-4 pt-4 sm:flex-row sm:justify-center">
            <Button asChild className="w-full sm:w-auto sm:min-w-32">
              <Link href={"/login"}>
                Get Started
                <ArrowRight className="ml-2" size={16} />
              </Link>
            </Button>
            <Button
              asChild
              className="w-full sm:w-auto sm:min-w-32"
              variant={"secondary"}
            >
              <Link href={"/docs"}>
                Documentation
                <Terminal className="ml-2" size={16} />
              </Link>
            </Button>
          </div>
        </div>
        <div className="flex items-center justify-center gap-8 pt-8">
          <div className="flex flex-col items-center gap-2 text-center">
            <div className="flex size-12 items-center justify-center rounded-full bg-secondary">
              <Smartphone className="text-muted-foreground" size={24} />
            </div>
            <span className="text-muted-foreground text-sm">
              Phone-initiated sessions
            </span>
          </div>
          <div className="flex flex-col items-center gap-2 text-center">
            <div className="flex size-12 items-center justify-center rounded-full bg-secondary">
              <Terminal className="text-muted-foreground" size={24} />
            </div>
            <span className="text-muted-foreground text-sm">
              CLI handoff mode
            </span>
          </div>
          <div className="flex flex-col items-center gap-2 text-center">
            <div className="flex size-12 items-center justify-center rounded-full bg-secondary">
              <Lock className="text-muted-foreground" size={24} />
            </div>
            <span className="text-muted-foreground text-sm">
              Zero-knowledge relay
            </span>
          </div>
        </div>
      </div>
    </section>
  );
}
