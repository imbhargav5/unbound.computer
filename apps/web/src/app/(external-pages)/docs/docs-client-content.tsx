"use client";
import { motion } from "motion/react";
import { Link } from "@/components/intl-link";

const fadeIn = {
  initial: { opacity: 0, y: 20 },
  animate: { opacity: 1, y: 0 },
  transition: { duration: 0.5 },
};

export function DocsClientContent() {
  return (
    <div className="relative mx-auto max-w-5xl px-6 py-20 lg:py-28">
      <div className="pointer-events-none absolute inset-0 flex items-start justify-center">
        <div className="mt-6 h-[360px] w-[720px] rounded-full bg-white/[0.05] blur-3xl" />
      </div>

      <div className="relative">
        <motion.h1
          className="mb-6 text-center font-light text-4xl text-white tracking-tight sm:text-5xl lg:text-6xl"
          data-testid="page-heading-title"
          {...fadeIn}
        >
          Documentation
        </motion.h1>

        <motion.p
          className="mx-auto mb-12 max-w-2xl text-center text-lg text-white/40 leading-relaxed lg:text-xl"
          {...fadeIn}
          transition={{ delay: 0.1 }}
        >
          A local-first AI coding assistant with native clients, a background
          daemon, and optional cloud sync.
        </motion.p>

        <motion.section
          className="mb-16"
          {...fadeIn}
          transition={{ delay: 0.2 }}
        >
          <h2 className="mb-4 font-light text-2xl text-white tracking-tight sm:text-3xl">
            Documentation Pages
          </h2>
          <p className="mb-8 max-w-3xl text-base text-white/50 leading-relaxed">
            Unbound is a development tool that pairs a background Rust daemon
            with native client applications to provide AI-assisted coding
            sessions.
          </p>
          <motion.div
            className="grid grid-cols-1 gap-6 md:grid-cols-3"
            {...fadeIn}
          >
            <Link className="block" href="/docs/overview">
              <div className="rounded-2xl border border-white/10 bg-white/[0.02] p-6 text-white transition duration-200 hover:-translate-y-0.5 hover:bg-white/[0.04]">
                <h3 className="mb-2 font-medium text-lg">Overview</h3>
                <p className="text-sm text-white/60">
                  The system follows a local-first architecture: all session
                  data lives in SQLite on your machine, and the daemon operates
                  fully offline.
                </p>
              </div>
            </Link>
            <Link className="block" href="/docs/about">
              <div className="rounded-2xl border border-white/10 bg-white/[0.02] p-6 text-white transition duration-200 hover:-translate-y-0.5 hover:bg-white/[0.04]">
                <h3 className="mb-2 font-medium text-lg">About</h3>
                <p className="text-sm text-white/60">
                  When signed in, sessions optionally sync to Supabase with
                  end-to-end encryption, enabling cross-device access through
                  the web app.
                </p>
              </div>
            </Link>
            <Link className="block" href="/docs/internals">
              <div className="rounded-2xl border border-white/10 bg-white/[0.02] p-6 text-white transition duration-200 hover:-translate-y-0.5 hover:bg-white/[0.04]">
                <h3 className="mb-2 font-medium text-lg">Internals</h3>
                <p className="text-sm text-white/60">
                  The Rust daemon is organized into focused crates under
                  apps/daemon/crates.
                </p>
              </div>
            </Link>
          </motion.div>
        </motion.section>

        <motion.section
          className="mb-12"
          {...fadeIn}
          transition={{ delay: 0.2 }}
        >
          <h2 className="mb-4 font-light text-2xl text-white tracking-tight sm:text-3xl">
            Internals Highlights
          </h2>
          <ul className="list-inside list-disc space-y-3 text-white/60">
            <li>
              <Link
                className="text-white/80 underline underline-offset-4 hover:text-white"
                href="/docs/internals/apps"
              >
                Apps
              </Link>{" "}
              - macOS native app (SwiftUI), iOS app, web app (Next.js),
              database.
            </li>
            <li>
              <Link
                className="text-white/80 underline underline-offset-4 hover:text-white"
                href="/docs/internals/daemon"
              >
                Daemon Crates
              </Link>{" "}
              - Rust daemon crates under apps/daemon/crates.
            </li>
            <li>
              <Link
                className="text-white/80 underline underline-offset-4 hover:text-white"
                href="/docs/internals/packages"
              >
                Packages
              </Link>{" "}
              - protocol (shared message protocol types), crypto (E2E
              encryption), session (session management helpers).
            </li>
            <li>
              <Link
                className="text-white/80 underline underline-offset-4 hover:text-white"
                href="/docs/internals/web"
              >
                Web Internals
              </Link>{" "}
              - request memoization, RSC data, navigation helpers.
            </li>
          </ul>
        </motion.section>

        <motion.section
          className="mb-8"
          {...fadeIn}
          transition={{ delay: 0.3 }}
        >
          <h2 className="mb-4 font-light text-2xl text-white tracking-tight sm:text-3xl">
            Architecture Snapshot
          </h2>
          <p className="max-w-3xl text-base text-white/60 leading-relaxed">
            Clients connect to the daemon over a Unix domain socket using an
            NDJSON-based protocol. The daemon spawns and manages Claude CLI
            processes, persists all session data to SQLite, and syncs encrypted
            messages through two paths.
          </p>
        </motion.section>
      </div>
    </div>
  );
}
