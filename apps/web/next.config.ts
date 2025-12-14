import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();

// import { withSentryConfig } from "@sentry/nextjs";
import type { NextConfig } from "next";
import { PHASE_DEVELOPMENT_SERVER } from "next/dist/shared/lib/constants";
import createNextIntlPlugin from "next-intl/plugin";

const withNextIntl = createNextIntlPlugin();

export default async function config(
  phase: string,
  defaults: { defaultConfig: NextConfig }
) {
  const nextConfig: NextConfig = {
    pageExtensions: ["js", "jsx", "ts", "tsx", "md", "mdx"],
    images: {
      remotePatterns: [
        {
          protocol: "http",
          hostname: "localhost",
          port: "54321",
          pathname: "/**",
        },
        {
          protocol: "https",
          hostname: "*.dicebear.com",
          port: "",
          pathname: "/**",
        },

        {
          protocol: "https",
          hostname: "placehold.co",
          port: "",
          pathname: "/**",
        },
        {
          protocol: "http",
          hostname: "localhost",
          port: "",
          pathname: "/**",
        },
        {
          protocol: "http",
          hostname: "localhost",
          port: "3000",
          pathname: "/**",
        },
        {
          protocol: "http",
          hostname: "localhost",
          port: "54321",
          pathname: "/**",
        },
        {
          protocol: "http",
          hostname: "127.0.0.1",
          port: "54321",
          pathname: "/**",
        },
        {
          protocol: "https",
          hostname: "*.supabase.co",
          port: "",
          pathname: "/**",
        },
        {
          protocol: "https",
          hostname: "*.supabase.com",
          port: "",
          pathname: "/**",
        },
        {
          protocol: "https",
          hostname: "*.gravatar.com",
          port: "",
          pathname: "/**",
        },
        {
          protocol: "https",
          hostname: "images.unsplash.com",
          port: "",
          pathname: "/**",
        },
        {
          protocol: "https",
          hostname: "github.com",
          port: "",
          pathname: "/**",
        },
        {
          protocol: "https",
          hostname: "oaidalleapiprodscus.blob.core.windows.net",
          port: "",
          pathname: "/**",
        },
      ],
    },

    reactStrictMode: true,
    turbopack: {
      rules: {
        "*.svg": {
          loaders: ["@svgr/webpack"],
          as: "*.js",
        },
      },
    },
    cacheComponents: true,
    experimental: {
      authInterrupts: true,
    },
  };
  if (phase === PHASE_DEVELOPMENT_SERVER) {
    // If you want to use sentry, uncomment the following line
    // nextConfig.sentry = {
    //   hideSourceMaps: false,
    // };
    nextConfig.logging = {
      incomingRequests: true,
      fetches: {
        fullUrl: true,
      },
    };
  }

  const modifiedConfig = withMDX(withNextIntl(nextConfig));

  // If you want to use sentry, uncomment the following line
  // return withSentryConfig(modifiedConfig);
  return modifiedConfig;
}
