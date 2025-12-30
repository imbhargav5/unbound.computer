"use client";

import { GitBranch, Laptop, Lock, Monitor, Smartphone } from "lucide-react";
import type React from "react";
import { forwardRef, useRef } from "react";
import { AnimatedBeam } from "@/components/magicui/animated-beam";
import { cn } from "@/lib/utils";

const Circle = forwardRef<
  HTMLDivElement,
  { className?: string; children?: React.ReactNode; label?: string }
>(({ className, children, label }, ref) => (
  <div className="flex flex-col items-center gap-3">
    <div
      className={cn(
        "z-10 flex size-12 items-center justify-center rounded-full border border-white/20 bg-black p-3",
        className
      )}
      ref={ref}
    >
      {children}
    </div>
    {label && (
      <span className="max-w-24 text-center text-white/40 text-xs">
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
        "relative flex h-[350px] w-full items-center justify-center overflow-hidden rounded-lg border border-white/10 bg-black p-10",
        className
      )}
      ref={containerRef}
    >
      <div className="flex size-full max-w-2xl flex-row items-center justify-between gap-6">
        <div className="flex flex-col justify-center">
          <Circle label="Mobile App" ref={mobileRef}>
            <Smartphone className="size-6 text-white" />
          </Circle>
        </div>
        <div className="flex flex-col justify-center">
          <Circle className="size-14" label="Relay Server" ref={relayRef}>
            <Lock className="size-7 text-white" />
          </Circle>
        </div>
        <div className="flex flex-col justify-center">
          <Circle className="size-14" label="Unbound Daemon" ref={daemonRef}>
            <Laptop className="size-7 text-white" />
          </Circle>
        </div>
        <div className="flex flex-col justify-center gap-4">
          <Circle label="Claude Code" ref={claudeRef}>
            <Monitor className="size-6 text-white" />
          </Circle>
          <Circle label="Git Repos" ref={repoRef}>
            <GitBranch className="size-6 text-white/50" />
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
    <section className="mx-auto flex max-w-5xl flex-col items-center justify-center space-y-12 overflow-hidden px-6 py-20">
      <div className="text-center">
        <p className="mb-4 font-medium text-sm text-white/40 uppercase tracking-widest">
          Architecture
        </p>
        <h2 className="mb-4 font-light text-3xl text-white lg:text-4xl">
          Zero-Knowledge Infrastructure
        </h2>
        <p className="mx-auto max-w-2xl text-white/40 leading-relaxed">
          Your phone connects to a relay server that forwards encrypted messages
          to your development machine. The relay never sees your code or
          commands.
        </p>
      </div>

      <AnimatedBeamArchitecture />

      <div className="grid max-w-4xl grid-cols-1 gap-6 md:grid-cols-3">
        <div className="rounded-lg border border-white/10 p-6">
          <h3 className="mb-2 font-medium text-white">Server is Untrusted</h3>
          <p className="text-sm text-white/40">
            The relay server cannot decrypt your messages or see your code.
          </p>
        </div>
        <div className="rounded-lg border border-white/10 p-6">
          <h3 className="mb-2 font-medium text-white">Relay is Crypto-Blind</h3>
          <p className="text-sm text-white/40">
            All communication is encrypted end-to-end between your devices.
          </p>
        </div>
        <div className="rounded-lg border border-white/10 p-6">
          <h3 className="mb-2 font-medium text-white">Keys Stay Local</h3>
          <p className="text-sm text-white/40">
            Master encryption keys never leave your trusted devices.
          </p>
        </div>
      </div>
    </section>
  );
}
