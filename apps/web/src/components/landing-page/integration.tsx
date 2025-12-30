"use client";

import {
  GitBranch,
  Laptop,
  Lock,
  Monitor,
  Server,
  Smartphone,
} from "lucide-react";
import type React from "react";
import { forwardRef, useRef } from "react";
import { AnimatedBeam } from "@/components/magicui/animated-beam";
import { cn } from "@/lib/utils";
import TitleBlock from "../title-block";

const Circle = forwardRef<
  HTMLDivElement,
  { className?: string; children?: React.ReactNode; label?: string }
>(({ className, children, label }, ref) => (
  <div className="flex flex-col items-center gap-2">
    <div
      className={cn(
        "z-10 flex size-12 items-center justify-center rounded-full border-2 bg-white p-3 shadow-[0_0_20px_-12px_rgba(0,0,0,0.8)] dark:bg-slate-800",
        className
      )}
      ref={ref}
    >
      {children}
    </div>
    {label && (
      <span className="max-w-20 text-center text-muted-foreground text-xs">
        {label}
      </span>
    )}
  </div>
));

Circle.displayName = "Circle";

export function AnimatedBeamArchitecture({
  className,
}: {
  className?: string;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mobileRef = useRef<HTMLDivElement>(null);
  const relayRef = useRef<HTMLDivElement>(null);
  const daemonRef = useRef<HTMLDivElement>(null);
  const claudeRef = useRef<HTMLDivElement>(null);
  const repoRef = useRef<HTMLDivElement>(null);

  return (
    <div
      className={cn(
        "relative flex h-[400px] w-full items-center justify-center overflow-hidden rounded-lg border bg-background p-10 md:shadow-xl",
        className
      )}
      ref={containerRef}
    >
      <div className="flex size-full max-w-2xl flex-row items-center justify-between gap-6">
        <div className="flex flex-col justify-center">
          <Circle label="Mobile App" ref={mobileRef}>
            <Smartphone className="size-6 text-blue-500" />
          </Circle>
        </div>
        <div className="flex flex-col justify-center">
          <Circle className="size-14" label="Relay Server" ref={relayRef}>
            <Lock className="size-7 text-green-500" />
          </Circle>
        </div>
        <div className="flex flex-col justify-center">
          <Circle className="size-14" label="Unbound Daemon" ref={daemonRef}>
            <Laptop className="size-7 text-purple-500" />
          </Circle>
        </div>
        <div className="flex flex-col justify-center gap-4">
          <Circle label="Claude Code" ref={claudeRef}>
            <Monitor className="size-6 text-orange-500" />
          </Circle>
          <Circle label="Git Repos" ref={repoRef}>
            <GitBranch className="size-6 text-slate-500" />
          </Circle>
        </div>
      </div>

      <AnimatedBeam
        containerRef={containerRef}
        duration={3}
        fromRef={mobileRef}
        toRef={relayRef}
      />
      <AnimatedBeam
        containerRef={containerRef}
        duration={3}
        fromRef={relayRef}
        toRef={daemonRef}
      />
      <AnimatedBeam
        containerRef={containerRef}
        duration={3}
        fromRef={daemonRef}
        toRef={claudeRef}
      />
      <AnimatedBeam
        containerRef={containerRef}
        duration={3}
        fromRef={daemonRef}
        toRef={repoRef}
      />
    </div>
  );
}

export default function Integration() {
  return (
    <section className="mx-auto flex max-w-6xl flex-col items-center justify-center space-y-10 overflow-hidden py-16">
      <div className="px-6">
        <TitleBlock
          icon={<Server size={16} />}
          section="Architecture"
          subtitle="Your phone connects to a relay server that forwards encrypted messages to your development machine. The relay never sees your code or commands - everything is end-to-end encrypted."
          title="Zero-Knowledge Infrastructure"
        />
      </div>

      <AnimatedBeamArchitecture />

      <div className="grid max-w-4xl grid-cols-1 gap-6 px-6 md:grid-cols-3">
        <div className="rounded-lg border bg-card p-4">
          <h3 className="font-medium">Server is Untrusted</h3>
          <p className="mt-2 text-muted-foreground text-sm">
            The relay server cannot decrypt your messages or see your code.
          </p>
        </div>
        <div className="rounded-lg border bg-card p-4">
          <h3 className="font-medium">Relay is Crypto-Blind</h3>
          <p className="mt-2 text-muted-foreground text-sm">
            All communication is encrypted end-to-end between your devices.
          </p>
        </div>
        <div className="rounded-lg border bg-card p-4">
          <h3 className="font-medium">Keys Stay Local</h3>
          <p className="mt-2 text-muted-foreground text-sm">
            Master encryption keys never leave your trusted devices.
          </p>
        </div>
      </div>
    </section>
  );
}
