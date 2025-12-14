/** @type {import('vite').UserConfig} */

import path from "node:path";
import { fileURLToPath } from "node:url";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
  },
  // path alias
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
});
