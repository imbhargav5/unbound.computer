import { expect, test } from "@playwright/test";
import Chance from "chance";
import { ensureSidebarIsOpen } from "../_helpers/sidebar.helper";
import {
  goToWorkspaceArea,
  matchPathAndExtractWorkspaceInfo,
} from "../_helpers/workspace.helper";

const chance = new Chance();

test.describe
  .serial("Team Workspace", () => {
    let workspaceSlug: string;

    test.beforeAll(async ({ browser }) => {
      const context = await browser.newContext({
        storageState: "playwright/.auth/user_1.json",
      });
      const page = await context.newPage();
      await page.goto("/dashboard", {
        waitUntil: "domcontentloaded",
        timeout: 30_000,
      });

      // Wait for page to fully load
      await page.waitForLoadState("networkidle");

      // Ensure sidebar is open before interacting with it
      await ensureSidebarIsOpen(page);

      // Wait for workspace switcher to load (inside Suspense) and click it
      const workspaceSwitcher = page.getByTestId("workspace-switcher-trigger");
      await workspaceSwitcher.waitFor();
      await workspaceSwitcher.click();

      // Click Create Workspace in dropdown
      await page.getByTestId("ws-create-workspace-trigger").click();

      const form = page.getByTestId("create-workspace-form");
      await form.waitFor({ timeout: 10_000 });
      await form.locator("input#name").fill("Team Workspace Test");
      const slug = await form.getByTestId("workspace-slug-input").inputValue();
      await form.getByRole("button", { name: "Create Workspace" }).click();
      await page.waitForURL(new RegExp(`/workspace/${slug}/home`));

      // Extract workspace info
      const workspaceInfo = await matchPathAndExtractWorkspaceInfo({ page });
      workspaceSlug = workspaceInfo.workspaceSlug;
      await context.close();
    });

    test("should navigate to workspace settings", async ({ page }) => {
      await goToWorkspaceArea({
        page,
        area: "settings",
        workspaceSlug,
      });
      const heading = page.getByRole("heading", {
        name: "Edit Workspace Title",
      });
      await heading.waitFor({ state: "visible", timeout: 15_000 });
      await expect(heading).toBeVisible();
    });

    test("should list team members", async ({ page }) => {
      await goToWorkspaceArea({
        page,
        area: "settings/members",
        workspaceSlug,
      });
      await expect(
        page.getByRole("heading", { name: "Team Members" })
      ).toBeVisible();
      await expect(page.getByTestId("members-table").first()).toBeVisible();
    });

    test("should update workspace title and slug", async ({ page }) => {
      await goToWorkspaceArea({
        page,
        area: "settings",
        workspaceSlug,
      });

      const newTitle = chance.word();
      const titleInput = page.getByTestId("edit-workspace-title-input").first();
      await titleInput.clear();
      await titleInput.fill(newTitle);

      // Wait for the slug to be automatically generated
      await page.waitForTimeout(500);
      // get slug
      const newSlug = await page
        .getByTestId("edit-workspace-slug-input")
        .inputValue();

      await page.getByRole("button", { name: "Update" }).click();

      await page.waitForURL(`/workspace/${newSlug}/home`, {
        waitUntil: "domcontentloaded",
        timeout: 30_000,
      });
      const { workspaceSlug: extractedSlug } =
        await matchPathAndExtractWorkspaceInfo({ page });
      expect(extractedSlug).toBe(newSlug);
    });
  });
