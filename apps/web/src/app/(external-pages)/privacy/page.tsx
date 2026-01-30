import { Terminal } from "lucide-react";
import type { Metadata } from "next";
import { Link } from "@/components/intl-link";

export const metadata: Metadata = {
  title: "Privacy Policy | Unbound",
  description: "Privacy Policy for Unbound",
};

export default async function PrivacyPage() {
  return (
    <div className="dark min-h-screen bg-black">
      <div className="mx-auto max-w-3xl px-6 py-16 lg:py-24">
        {/* Header */}
        <div className="mb-12">
          <Link className="mb-8 inline-flex items-center gap-2" href="/">
            <div className="flex size-8 items-center justify-center rounded-lg border border-white/20">
              <Terminal className="size-4 text-white" />
            </div>
            <span className="font-medium text-lg text-white">Unbound</span>
          </Link>
          <h1 className="mb-4 font-light text-4xl text-white">
            Privacy Policy
          </h1>
          <p className="text-white/40">Last updated: December 2024</p>
        </div>

        {/* Content */}
        <div className="space-y-10">
          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              1. Introduction
            </h2>
            <p className="text-white/60 leading-relaxed">
              Unbound ("we", "our", or "us") is committed to protecting your
              privacy. This Privacy Policy explains how we collect, use, and
              safeguard your information when you use our service for remote
              Claude Code execution.
            </p>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              2. Our Zero-Knowledge Architecture
            </h2>
            <p className="text-white/60 leading-relaxed">
              Unbound is designed with privacy as a core principle. Our
              zero-knowledge architecture means:
            </p>
            <ul className="mt-4 ml-4 list-disc space-y-2 pl-4 text-white/60">
              <li>
                <strong className="text-white/80">
                  We cannot read your code:
                </strong>{" "}
                All communications between your devices are end-to-end
                encrypted. The relay server cannot decrypt your messages.
              </li>
              <li>
                <strong className="text-white/80">
                  Keys stay on your devices:
                </strong>{" "}
                Your master encryption keys never leave your trusted devices.
              </li>
              <li>
                <strong className="text-white/80">Server is untrusted:</strong>{" "}
                Our infrastructure is designed assuming the server could be
                compromised - your data remains secure regardless.
              </li>
            </ul>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              3. Information We Collect
            </h2>
            <div className="space-y-4 text-white/60 leading-relaxed">
              <p>
                <strong className="text-white/80">Account Information:</strong>{" "}
                Email address and authentication credentials (hashed and
                salted).
              </p>
              <p>
                <strong className="text-white/80">Device Information:</strong>{" "}
                Device identifiers for pairing purposes, device type (Mac,
                Linux, Windows, iOS, Android).
              </p>
              <p>
                <strong className="text-white/80">Usage Metadata:</strong>{" "}
                Session timestamps, connection status, and aggregate usage
                statistics. We do not log the content of your sessions.
              </p>
              <p>
                <strong className="text-white/80">Payment Information:</strong>{" "}
                Processed by Stripe. We do not store credit card numbers.
              </p>
            </div>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              4. Information We Do NOT Collect
            </h2>
            <ul className="ml-4 list-disc space-y-2 pl-4 text-white/60">
              <li>Your source code or repository contents</li>
              <li>Claude Code session content or commands</li>
              <li>File contents from your development machine</li>
              <li>Git history or commit messages</li>
              <li>Any decrypted communication between your devices</li>
            </ul>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              5. How We Use Information
            </h2>
            <ul className="ml-4 list-disc space-y-2 pl-4 text-white/60">
              <li>To provide and maintain the Service</li>
              <li>To authenticate your devices and sessions</li>
              <li>To process payments and manage subscriptions</li>
              <li>To send important service notifications</li>
              <li>To improve and optimize the Service</li>
              <li>To detect and prevent fraud or abuse</li>
            </ul>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              6. Data Storage and Security
            </h2>
            <p className="text-white/60 leading-relaxed">
              Account data is stored in secure, encrypted databases. Session
              metadata is retained for 90 days for troubleshooting purposes,
              then automatically deleted. We use industry-standard security
              measures including TLS 1.3 for transport, XChaCha20-Poly1305 for
              end-to-end encryption, and X25519 for key exchange.
            </p>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              7. Third-Party Services
            </h2>
            <div className="space-y-4 text-white/60 leading-relaxed">
              <p>We use the following third-party services:</p>
              <ul className="ml-4 list-disc space-y-2 pl-4">
                <li>
                  <strong className="text-white/80">Supabase:</strong> Database
                  and authentication
                </li>
                <li>
                  <strong className="text-white/80">Stripe:</strong> Payment
                  processing
                </li>
                <li>
                  <strong className="text-white/80">Sentry:</strong> Error
                  tracking (no PII collected)
                </li>
                <li>
                  <strong className="text-white/80">PostHog:</strong> Anonymous
                  usage analytics
                </li>
              </ul>
            </div>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              8. Your Rights
            </h2>
            <p className="text-white/60 leading-relaxed">
              You have the right to access, correct, or delete your personal
              information. You can export your account data or request account
              deletion at any time through your account settings or by
              contacting us. We will respond to requests within 30 days.
            </p>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              9. Data Retention
            </h2>
            <p className="text-white/60 leading-relaxed">
              We retain your account information for as long as your account is
              active. Upon account deletion, we remove your personal data within
              30 days, except where retention is required by law. Anonymous,
              aggregated data may be retained indefinitely for analytics
              purposes.
            </p>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              10. Changes to This Policy
            </h2>
            <p className="text-white/60 leading-relaxed">
              We may update this Privacy Policy from time to time. We will
              notify you of significant changes by posting the new policy on
              this page and updating the "Last updated" date. Your continued use
              of the Service after changes constitutes acceptance.
            </p>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">11. Contact</h2>
            <p className="text-white/60 leading-relaxed">
              If you have questions about this Privacy Policy, please contact us
              at{" "}
              <a
                className="text-white underline underline-offset-4 hover:text-white/80"
                href="mailto:privacy@unbound.computer"
              >
                privacy@unbound.computer
              </a>
              .
            </p>
          </section>
        </div>

        {/* Footer */}
        <div className="mt-16 border-white/10 border-t pt-8">
          <Link className="text-sm text-white/40 hover:text-white" href="/">
            &larr; Back to home
          </Link>
        </div>
      </div>
    </div>
  );
}
