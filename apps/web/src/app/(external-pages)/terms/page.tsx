import { Terminal } from "lucide-react";
import type { Metadata } from "next";
import { Link } from "@/components/intl-link";

export const metadata: Metadata = {
  title: "Terms of Service | Unbound",
  description: "Terms of Service for Unbound",
};

export default async function TermsPage() {
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
            Terms of Service
          </h1>
          <p className="text-white/40">Last updated: December 2024</p>
        </div>

        {/* Content */}
        <div className="space-y-10">
          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              1. Acceptance of Terms
            </h2>
            <p className="text-white/60 leading-relaxed">
              By accessing or using Unbound ("Service"), you agree to be bound
              by these Terms of Service. If you do not agree to these terms, you
              may not use the Service. Unbound provides a platform for remote
              Claude Code execution from mobile devices with secure relay
              infrastructure.
            </p>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              2. Description of Service
            </h2>
            <p className="text-white/60 leading-relaxed">
              Unbound enables you to control Claude Code sessions on your
              development machine from your mobile device. The Service includes
              a CLI tool, relay server infrastructure, and mobile/web
              applications. All communications are end-to-end encrypted using
              zero-knowledge architecture.
            </p>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              3. User Responsibilities
            </h2>
            <div className="space-y-4 text-white/60 leading-relaxed">
              <p>You are responsible for:</p>
              <ul className="ml-4 list-disc space-y-2 pl-4">
                <li>
                  Maintaining the security of your devices and encryption keys
                </li>
                <li>All activities that occur under your account or devices</li>
                <li>
                  Ensuring your use of Claude Code complies with Anthropic's
                  terms
                </li>
                <li>Not using the Service for any unlawful purposes</li>
              </ul>
            </div>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              4. Security and Encryption
            </h2>
            <p className="text-white/60 leading-relaxed">
              Unbound uses end-to-end encryption to protect your communications.
              The relay server cannot decrypt your messages or access your code.
              Master encryption keys never leave your trusted devices. You
              acknowledge that security depends on the protection of your
              devices and credentials.
            </p>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              5. Intellectual Property
            </h2>
            <p className="text-white/60 leading-relaxed">
              The Service and its original content, features, and functionality
              are owned by Unbound and are protected by international copyright,
              trademark, and other intellectual property laws. Your code and
              data remain your property - we claim no ownership over content you
              create or transmit through the Service.
            </p>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              6. Limitation of Liability
            </h2>
            <p className="text-white/60 leading-relaxed">
              In no event shall Unbound be liable for any indirect, incidental,
              special, consequential, or punitive damages, including loss of
              profits, data, or other intangible losses, resulting from your use
              of or inability to use the Service. Our total liability shall not
              exceed the amount paid by you in the 12 months preceding the
              claim.
            </p>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              7. Termination
            </h2>
            <p className="text-white/60 leading-relaxed">
              We may terminate or suspend your access to the Service
              immediately, without prior notice, for conduct that we believe
              violates these Terms or is harmful to other users, us, or third
              parties, or for any other reason at our sole discretion.
            </p>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">
              8. Changes to Terms
            </h2>
            <p className="text-white/60 leading-relaxed">
              We reserve the right to modify these Terms at any time. We will
              notify you of significant changes by posting the new Terms on this
              page. Your continued use of the Service after changes constitutes
              acceptance of the new Terms.
            </p>
          </section>

          <section>
            <h2 className="mb-4 font-medium text-white text-xl">9. Contact</h2>
            <p className="text-white/60 leading-relaxed">
              If you have questions about these Terms, please contact us at{" "}
              <a
                className="text-white underline underline-offset-4 hover:text-white/80"
                href="mailto:legal@unbound.computer"
              >
                legal@unbound.computer
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
