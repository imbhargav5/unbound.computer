import type { Page } from "@playwright/test";

/**
 * Ensures the sidebar is in the expanded state.
 * If the sidebar is collapsed, it will click the trigger to expand it.
 *
 * @param page - The Playwright page object
 */
export async function ensureSidebarIsOpen(page: Page): Promise<void> {
  const sidebar = page.locator('[data-slot="sidebar"]');
  const sidebarState = await sidebar.getAttribute("data-state");
  console.log("sidebarState", sidebarState);
  if (sidebarState === "collapsed") {
    await page.getByTestId("sidebar-toggle-trigger").click();
    // Wait for sidebar to expand
    await page.waitForTimeout(300);
  }
}

/**
 * Ensures the sidebar is in the collapsed state.
 * If the sidebar is expanded, it will click the trigger to collapse it.
 *
 * @param page - The Playwright page object
 */
export async function ensureSidebarIsCollapsed(page: Page): Promise<void> {
  const sidebar = page.locator('[data-sidebar="sidebar"]');
  const sidebarState = await sidebar.getAttribute("data-state");

  if (sidebarState === "expanded") {
    await page.locator('[data-sidebar="trigger"]').click();
    // Wait for sidebar to collapse
    await page.waitForTimeout(300);
  }
}
