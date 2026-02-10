import { Terminal } from "lucide-react";
import { Link } from "@/components/intl-link";
import { footerItems, footerSocialItems } from "./footer-items";

export function Footer() {
  return (
    <footer className="border-white/10 border-t">
      <div className="mx-auto max-w-5xl px-6 py-12 lg:py-16">
        <div className="flex flex-col gap-12 lg:flex-row lg:justify-between">
          {/* Brand */}
          <div className="flex flex-col gap-4">
            <Link className="flex items-center gap-2" href="/">
              <div className="flex size-9 items-center justify-center rounded-lg border border-white/20">
                <Terminal className="size-5 text-white" />
              </div>
              <span className="font-medium text-white text-xl">Unbound</span>
            </Link>
            <p className="max-w-xs text-sm text-white/40">
              Run Claude Code on your machine from anywhere. Secure, encrypted,
              and always under your control.
            </p>
          </div>

          {/* Links — hidden for now */}
          <div className="hidden flex-wrap gap-12 lg:gap-16">
            {footerItems.map((item) => (
              <div key={item.title}>
                <h3 className="mb-4 font-medium text-white/40 text-xs uppercase tracking-widest">
                  {item.title}
                </h3>
                <ul className="space-y-3">
                  {item.items.map((link) => (
                    <li key={link.name}>
                      <Link
                        className="text-sm text-white/60 transition-colors hover:text-white"
                        href={link.url}
                      >
                        {link.name}
                      </Link>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        </div>

        {/* Bottom */}
        <div className="mt-12 flex flex-col items-center justify-between gap-4 border-white/10 border-t pt-8 md:flex-row">
          <p className="text-sm text-white/30">
            © {new Date().getFullYear()} Unbound. All Rights Reserved.
          </p>
          <div className="flex gap-4">
            {footerSocialItems.map((item) => (
              <Link
                className="text-white/40 transition-colors hover:text-white"
                href={item.url}
                key={item.name}
              >
                <item.icon />
                <span className="sr-only">{item.name}</span>
              </Link>
            ))}
          </div>
        </div>
      </div>
    </footer>
  );
}
