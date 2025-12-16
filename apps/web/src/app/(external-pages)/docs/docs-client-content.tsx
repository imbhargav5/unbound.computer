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
        Nextbase Ultimate ships with Fumadocs. Fumadocs is a powerful
        documentation framework integrated into Nextbase Ultimate, designed to
        make creating beautiful and functional documentation a breeze.
      </motion.p>

      <motion.section className="mb-8" {...fadeIn} transition={{ delay: 0.2 }}>
        <h2 className="mb-4 font-semibold text-2xl">Documentation Pages</h2>
        <motion.div
          className="grid grid-cols-1 gap-4 sm:grid-cols-2"
          {...fadeIn}
        >
          <Link className="block" href="/docs/getting-started">
            <div className="rounded-lg border border-primary bg-primary p-6 text-primary-foreground transition-colors hover:bg-primary/90">
              <h3 className="mb-2 font-semibold text-lg">Getting Started</h3>
              <p className="text-sm opacity-90">
                Quick start guide to help you begin working with the
                documentation
              </p>
            </div>
          </Link>
          <Link className="block" href="/docs/components">
            <div className="rounded-lg border border-primary bg-primary p-6 text-primary-foreground transition-colors hover:bg-primary/90">
              <h3 className="mb-2 font-semibold text-lg">Components</h3>
              <p className="text-sm opacity-90">
                Example components with code blocks and syntax highlighting
              </p>
            </div>
          </Link>
          <Link className="block" href="/docs/api-reference">
            <div className="rounded-lg border border-primary bg-primary p-6 text-primary-foreground transition-colors hover:bg-primary/90">
              <h3 className="mb-2 font-semibold text-lg">API Reference</h3>
              <p className="text-sm opacity-90">
                API documentation with tables and structured examples
              </p>
            </div>
          </Link>
          <Link className="block" href="/docs/test">
            <div className="rounded-lg border border-primary bg-primary p-6 text-primary-foreground transition-colors hover:bg-primary/90">
              <h3 className="mb-2 font-semibold text-lg">Test Page</h3>
              <p className="text-sm opacity-90">
                Original test page demonstrating Fumadocs features
              </p>
            </div>
          </Link>
        </motion.div>
      </motion.section>

      <motion.section className="mb-8" {...fadeIn} transition={{ delay: 0.2 }}>
        <h2 className="mb-4 font-semibold text-2xl">Key Features</h2>
        <ul className="list-inside list-disc space-y-2">
          <li>Sleek, responsive design out of the box</li>
          <li>Built-in search functionality for easy content discovery</li>
          <li>Automatic table of contents generation</li>
          <li>Support for MDX and React components</li>
          <li>Dark mode support</li>
          <li>SEO optimization</li>
        </ul>
      </motion.section>

      <motion.section className="mb-8" {...fadeIn} transition={{ delay: 0.3 }}>
        <h2 className="mb-4 font-semibold text-2xl">Getting Started</h2>
        <p className="mb-4">Using Fumadocs is straightforward:</p>
        <ol className="list-inside list-decimal space-y-2">
          <li>Create your documentation content in MDX files</li>
          <li>Ability to use content collections</li>
          <li>Use Fumadocs components to enhance your docs</li>
          <li>Customize the theme and layout as needed</li>
        </ol>
      </motion.section>

      <motion.section className="mb-8" {...fadeIn} transition={{ delay: 0.4 }}>
        <h2 className="mb-4 font-semibold text-2xl">Customization Options</h2>
        <p className="mb-4">Fumadocs offers extensive customization:</p>
        <ul className="list-inside list-disc space-y-2">
          <li>Theming: Adjust colors, typography, and spacing</li>
          <li>Layout: Modify sidebar, header, and footer components</li>
          <li>Components: Create custom MDX components</li>
          <li>Configuration: Fine-tune search, navigation, and more</li>
        </ul>
      </motion.section>
    </div>
  );
}
