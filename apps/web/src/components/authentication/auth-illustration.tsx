import { Lock, Monitor, Smartphone, Terminal } from "lucide-react";

export function AuthIllustration() {
  return (
    <>
      {/* Subtle gradient background */}
      <div className="absolute inset-0 bg-gradient-to-br from-white/[0.02] to-transparent" />

      {/* Main content */}
      <div className="relative z-10 flex flex-col items-center gap-12 p-12">
        {/* Architecture preview */}
        <div className="flex items-center gap-8">
          <div className="flex flex-col items-center gap-2">
            <div className="flex size-14 items-center justify-center rounded-full border border-white/20 bg-white/[0.02]">
              <Smartphone className="size-6 text-white/70" />
            </div>
            <span className="text-white/30 text-xs">Phone</span>
          </div>

          <div className="h-px w-12 bg-gradient-to-r from-white/20 to-white/5" />

          <div className="flex flex-col items-center gap-2">
            <div className="flex size-16 items-center justify-center rounded-full border border-white/20 bg-white/[0.02]">
              <Lock className="size-7 text-white/70" />
            </div>
            <span className="text-white/30 text-xs">Encrypted</span>
          </div>

          <div className="h-px w-12 bg-gradient-to-r from-white/5 to-white/20" />

          <div className="flex flex-col items-center gap-2">
            <div className="flex size-14 items-center justify-center rounded-full border border-white/20 bg-white/[0.02]">
              <Monitor className="size-6 text-white/70" />
            </div>
            <span className="text-white/30 text-xs">Machine</span>
          </div>
        </div>

        {/* Terminal mockup */}
        <div className="w-full max-w-sm rounded-lg border border-white/10 bg-white/[0.02] p-4">
          <div className="mb-3 flex items-center gap-2">
            <div className="size-2.5 rounded-full bg-white/20" />
            <div className="size-2.5 rounded-full bg-white/20" />
            <div className="size-2.5 rounded-full bg-white/20" />
          </div>
          <div className="space-y-2 font-mono text-sm">
            <p className="text-white/40">
              <span className="text-white/60">$</span> unbound link
            </p>
            <p className="text-white/30">Pairing with device...</p>
            <p className="text-white/50">
              <span className="text-green-400/70">✓</span> Connected securely
            </p>
          </div>
        </div>

        {/* Tagline */}
        <div className="text-center">
          <p className="mb-2 font-light text-white/60 text-xl">
            Code from anywhere
          </p>
          <p className="text-sm text-white/30">
            Zero-knowledge encryption keeps your code safe
          </p>
        </div>

        {/* Feature badges */}
        <div className="flex items-center gap-3">
          <div className="flex items-center gap-2 rounded-full border border-white/10 px-3 py-1.5">
            <Terminal className="size-3.5 text-white/50" />
            <span className="text-white/40 text-xs">CLI First</span>
          </div>
          <div className="flex items-center gap-2 rounded-full border border-white/10 px-3 py-1.5">
            <Lock className="size-3.5 text-white/50" />
            <span className="text-white/40 text-xs">E2E Encrypted</span>
          </div>
        </div>
      </div>

      {/* Background grid pattern */}
      <div
        className="pointer-events-none absolute inset-0 opacity-[0.02]"
        style={{
          backgroundImage: `url("data:image/svg+xml,%3Csvg width='60' height='60' viewBox='0 0 60 60' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' fillRule='evenodd'%3E%3Cg fill='%23ffffff' fillOpacity='1'%3E%3Cpath d='M36 34v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zm0-30V0h-2v4h-4v2h4v4h2V6h4V4h-4zM6 34v-4H4v4H0v2h4v4h2v-4h4v-2H6zM6 4V0H4v4H0v2h4v4h2V6h4V4H6z'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E")`,
        }}
      />
    </>
  );
}
