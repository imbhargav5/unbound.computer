import { expect, test } from "@playwright/test";
import { Chance } from "chance";
import {
  goToWorkspaceArea,
  matchPathAndExtractWorkspaceInfo,
} from "../_helpers/workspace.helper";

test.describe.serial("Solo Workspace", () => {
  let workspaceSlug: string;
  let isSoloWorkspace: boolean;

  test.beforeAll(async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto("/dashboard");
    const workspaceInfo = await matchPathAndExtractWorkspaceInfo({ page });
    workspaceSlug = workspaceInfo.workspaceSlug;
    isSoloWorkspace = workspaceInfo.isSoloWorkspace;
    await context.close();
  });

  test("should navigate to workspace settings", async ({ page }) => {
    await goToWorkspaceArea({
      page,
      area: "settings",
      workspaceSlug,
      isSoloWorkspace,
    });
    await expect(
      page.getByRole("heading", { name: "Edit Workspace Title" }),
    ).toBeVisible();
  });

  // test("should list team members", async ({ page }) => {
  //   await goToWorkspaceArea({
  //     page,
  //     area: "settings/members",
  //     workspaceSlug,
  //     isSoloWorkspace,
  //   });
  //   await expect(
  //     page.getByRole("heading", { name: "Team Members" }),
  //   ).toBeVisible();
  //   await expect(page.getByTestId("members-table")).toBeVisible();
  // });

  test("should update workspace title and slug", async ({ page }) => {
    await goToWorkspaceArea({
      page,
      area: "settings",
      workspaceSlug,
      isSoloWorkspace,
    });

    const newTitle = new Chance().word();
    const titleInput = page.getByTestId("edit-workspace-title-input");
    await titleInput.fill(newTitle);

    // Wait for the slug to be automatically generated
    await page.waitForTimeout(500);

    // Get the current title before update
    const workspaceNameElement = page.getByTestId("workspaceName");
    const oldTitle = await workspaceNameElement.textContent();

    await page.getByRole("button", { name: "Update" }).click();

    if (oldTitle) {
      // First wait for old value to disappear
      await expect(workspaceNameElement).not.toHaveText(oldTitle, {
        timeout: 15000,
      });
    }
    // Then verify the new value
    await expect(workspaceNameElement).toHaveText(newTitle, { timeout: 15000 });
  });
});

test.describe.serial("Team Workspace", () => {
  let workspaceSlug: string;
  let isSoloWorkspace: boolean;

  test.beforeAll(async ({ browser }) => {
    const context = await browser.newContext();
    const page = await context.newPage();
    await page.goto("/dashboard");

    // Create a team workspace
    await page.focus("body");
    await page.keyboard.press("w");
    const form = page.getByTestId("create-workspace-form");
    await form.waitFor();
    await form.locator("input#name").fill("Team Workspace Test");
    const slug = await form.getByTestId("workspace-slug-input").inputValue();
    await form.getByRole("button", { name: "Create Workspace" }).click();
    await page.waitForURL(new RegExp(`/[a-z]{2}/workspace/${slug}/home`));

    // Extract workspace info
    const workspaceInfo = await matchPathAndExtractWorkspaceInfo({ page });
    workspaceSlug = workspaceInfo.workspaceSlug;
    isSoloWorkspace = workspaceInfo.isSoloWorkspace;
    await context.close();
  });

  test("should navigate to workspace settings", async ({ page }) => {
    await goToWorkspaceArea({
      page,
      area: "settings",
      workspaceSlug,
      isSoloWorkspace,
    });
    await expect(
      page.getByRole("heading", { name: "Edit Workspace Title" }),
    ).toBeVisible();
  });

  test("should list team members", async ({ page }) => {
    await goToWorkspaceArea({
      page,
      area: "settings/members",
      workspaceSlug,
      isSoloWorkspace,
    });
    await expect(
      page.getByRole("heading", { name: "Team Members" }),
    ).toBeVisible();
    await expect(page.getByTestId("members-table")).toBeVisible();
  });

  test("should update workspace title and slug", async ({ page }) => {
    await goToWorkspaceArea({
      page,
      area: "settings",
      workspaceSlug,
      isSoloWorkspace,
    });

    const newTitle = new Chance().word();
    const titleInput = page.getByTestId("edit-workspace-title-input");
    await titleInput.fill(newTitle);

    // Wait for the slug to be automatically generated
    await page.waitForTimeout(500);

    // Get the current title before update
    const workspaceNameElement = page.getByTestId("workspaceName");
    const oldTitle = await workspaceNameElement.textContent();

    await page.getByRole("button", { name: "Update" }).click();

    // First wait for old value to disappear
    if (oldTitle) {
      gq;
      await expect(workspaceNameElement).not.toHaveText(oldTitle, {
        timeout: 15000,
      });
    }
    // Then verify the new value
    await expect(workspaceNameElement).toHaveText(newTitle, { timeout: 15000 });
  });
});
