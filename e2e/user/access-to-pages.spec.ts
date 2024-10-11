import { expect, test } from "@playwright/test";

test("Logged in users can see home page", async ({ page }) => {
  // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
  await page.goto("/");
  await expect(page.locator("h1")).toContainText(
    "Nextbase Ultimate Landing Page",
  );
});

test("Logged in users can see feedback page", async ({ page }) => {
  // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
  await page.goto("/en/feedback");
  await expect(
    page.getByRole("heading", { name: "Community Feedback" }),
  ).toBeVisible();
});

test("Logged in users can see docs page", async ({ page }) => {
  // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
  await page.goto("/en/docs");
  await expect(
    page.getByRole("heading", { name: "Documentation " }),
  ).toBeVisible();
});

test("Logged in users can see blog page", async ({ page }) => {
  // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
  await page.goto("/en/blog");
  await expect(
    page.getByRole("heading", { name: "All Blog Posts " }),
  ).toBeVisible();
});

test("Logged in users can see roadmap page", async ({ page }) => {
  // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
  await page.goto("/en/roadmap");
  await expect(page.getByRole("heading", { name: "Roadmap " })).toBeVisible();
});

test("Logged in users can see changelog page", async ({ page }) => {
  // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
  await page.goto("/en/changelog");
  await expect(page.getByTestId("page-heading-title")).toContainText(
    "Changelog",
  );
});

test("Logged in users can see terms page", async ({ page }) => {
  // Start from the index page (the baseURL is set via the webServer in the playwright.config.ts)
  await page.goto("/en/terms");
  await expect(
    page.getByRole("heading", { name: "Terms of Service " }),
  ).toBeVisible();
});

test("Logged in users can see dashboard", async ({ page }) => {
  await page.goto("/en/dashboard");
  await page.getByTestId("dashboard-title").waitFor();
});

test("Anon users can not see admin", async ({ page }) => {
  // expect that they are redirected to workspace dashboard page
  await page.goto("/en/app_admin");
  await page.getByTestId("dashboard-title").waitFor();
});
