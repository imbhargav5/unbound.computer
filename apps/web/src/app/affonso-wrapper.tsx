"use client";
import Script from "next/script";

export function AffonsoWrapper() {
  const isProd = process.env.NODE_ENV === "production";

  if (!isProd) {
    return null;
  }

  return (
    <Script
      data-affonso="cm9ibn9ao000dq5k3gyw905jo"
      data-cookie_duration="30"
      src="https://affonso.io/js/pixel.min.js"
      strategy="afterInteractive"
    />
  );
}
