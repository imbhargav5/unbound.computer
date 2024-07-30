import { devices, type PlaywrightTestConfig } from "@playwright/test";
import path from "path";

// Use process.env.PORT by default and fallback to port 3000
const PORT = process.env.PORT || 3000;

// Set webServer.url and use.baseURL with the location of the WebServer respecting the correct set port
const baseURL = `http://localhost:${PORT}`;

// Reference: https://playwright.dev/docs/test-configuration
const config: PlaywrightTestConfig = {
  // highest number of workers in a m3 pro max
  workers: 4,
  // Timeout per test
  timeout: 120 * 1000,
  // Test directory
  testDir: path.join(__dirname, "e2e"),
  // If a test fails, retry it additional 2 times
  retries: 2,
  // Artifacts folder where screenshots, videos, and traces are stored.
  outputDir: "test-results/",

  // Run your local dev server before starting the tests:
  // https://playwright.dev/docs/test-advanced#launching-a-development-web-server-during-the-tests
  webServer: {
    command: "cross-env NODE_ENV=test pnpm dev",
    url: baseURL,
    timeout: 120 * 1000,
    // reuseExistingServer: !process.env.CI,
  },

  use: {
    // Use baseURL so to make navigations relative.
    // More information: https://playwright.dev/docs/api/class-testoptions#test-options-base-url
    baseURL,

    // Retry a test if its failing with enabled tracing. This allows you to analyse the DOM, console logs, network traffic etc.
    // More information: https://playwright.dev/docs/trace-viewer
    trace: "retry-with-trace",

    actionTimeout: 60 * 1000,


    // All available context options: https://playwright.dev/docs/api/class-browser#browser-new-context
    // contextOptions: {
    //   ignoreHTTPSErrors: true,
    // },
  },

  projects: [
    {
      name: "with-auth",
      testMatch: "_setups/user.setup.ts",
    },
    {
      name: "with-app-admin",
      testMatch: "_setups/admin.setup.ts",
    },
    {
      name: "admin-users",
      testMatch: "admin/**/*.spec.ts",
      retries: 0,
      dependencies: ["with-app-admin"],
      use: {
        ...devices["Desktop Chrome"],
        // storage state is loaded within test cases
      },
    },
    {
      name: "logged-in-users",
      testMatch: "user/**/*.spec.ts",
      retries: 0,
      dependencies: ["with-auth"],
      use: {
        ...devices["Desktop Chrome"],
        storageState: "playwright/.auth/user.json",
      },
    },
    {
      name: "anon-users",
      testMatch: "anon/**/*.spec.ts",
      use: {
        ...devices["Desktop Chrome"],
      },
    },
  ],
  globalSetup: "./playwright/global-setup.ts",
};
export default config;
