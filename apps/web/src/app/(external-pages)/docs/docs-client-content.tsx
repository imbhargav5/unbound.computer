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
    <div className="mx-auto max-w-3xl max-w-4xl px-4 py-12">
      <motion.h1
        className="mb-6 font-bold text-4xl"
        data-testid="page-heading-title"
        {...fadeIn}
      >
        Documentation
      </motion.h1>

      <motion.p
        className="mb-8 text-lg"
        {...fadeIn}
        transition={{ delay: 0.1 }}
      >
        A local-first AI coding assistant with native clients, a background
        daemon, and optional cloud sync.
      </motion.p>

      <motion.section className="mb-8" {...fadeIn} transition={{ delay: 0.2 }}>
        <h2 className="mb-4 font-semibold text-2xl">Documentation Pages</h2>
        <p className="mb-6 text-base text-muted-foreground">
          Unbound is a development tool that pairs a background Rust daemon with
          native client applications to provide AI-assisted coding sessions.
        </p>
        <motion.div
          className="grid grid-cols-1 gap-4 sm:grid-cols-2"
          {...fadeIn}
        >
          <Link className="block" href="/docs/overview">
            <div className="rounded-lg border border-primary bg-primary p-6 text-primary-foreground transition-colors hover:bg-primary/90">
              <h3 className="mb-2 font-semibold text-lg">Overview</h3>
              <p className="text-sm opacity-90">
                The system follows a local-first architecture: all session data
                lives in SQLite on your machine, and the daemon operates fully
                offline.
              </p>
            </div>
          </Link>
          <Link className="block" href="/docs/about">
            <div className="rounded-lg border border-primary bg-primary p-6 text-primary-foreground transition-colors hover:bg-primary/90">
              <h3 className="mb-2 font-semibold text-lg">About</h3>
              <p className="text-sm opacity-90">
                When signed in, sessions optionally sync to Supabase with
                end-to-end encryption, enabling cross-device access through the
                web app.
              </p>
            </div>
          </Link>
          <Link className="block" href="/docs/internals">
            <div className="rounded-lg border border-primary bg-primary p-6 text-primary-foreground transition-colors hover:bg-primary/90">
              <h3 className="mb-2 font-semibold text-lg">Internals</h3>
              <p className="text-sm opacity-90">
                The Rust daemon is organized into focused crates under
                apps/daemon/crates.
              </p>
            </div>
          </Link>
        </motion.div>
      </motion.section>

      <motion.section className="mb-8" {...fadeIn} transition={{ delay: 0.2 }}>
        <h2 className="mb-4 font-semibold text-2xl">Internals Highlights</h2>
        <ul className="list-inside list-disc space-y-2">
          <li>
            <Link className="underline" href="/docs/internals/apps">
              Apps
            </Link>{" "}
            - macOS native app (SwiftUI), iOS app, web app (Next.js), database.
          </li>
          <li>
            <Link className="underline" href="/docs/internals/daemon">
              Daemon Crates
            </Link>{" "}
            - Rust daemon crates under apps/daemon/crates.
          </li>
          <li>
            <Link className="underline" href="/docs/internals/packages">
              Packages
            </Link>{" "}
            - protocol (shared message protocol types), crypto (E2E encryption),
            session (session management helpers).
          </li>
          <li>
            <Link className="underline" href="/docs/internals/web">
              Web Internals
            </Link>{" "}
            - request memoization, RSC data, navigation helpers.
          </li>
        </ul>
      </motion.section>

      <motion.section className="mb-8" {...fadeIn} transition={{ delay: 0.3 }}>
        <h2 className="mb-4 font-semibold text-2xl">Architecture Snapshot</h2>
        <p className="mb-4">
          Clients connect to the daemon over a Unix domain socket using an
          NDJSON-based protocol. The daemon spawns and manages Claude CLI
          processes, persists all session data to SQLite, and syncs encrypted
          messages through two paths.
        </p>
      </motion.section>
    </div>
  );
}
