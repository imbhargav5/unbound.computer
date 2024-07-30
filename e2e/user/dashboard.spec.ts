import { expect, test } from '@playwright/test';
import { dashboardDefaultOrganizationIdHelper } from '../_helpers/dashboard-default-organization-id.helper';

test('dashboard for a user with profile', async ({ page }) => {
  const organizationSlug = await dashboardDefaultOrganizationIdHelper({ page });
  const settingsPageURL = `/${organizationSlug}/settings`;
  const billingPageURL = `/${organizationSlug}/settings/billing`;
  const membersPageURL = `/${organizationSlug}/settings/members`;

  // check for the presence of the settings page
  await page.goto(settingsPageURL);
  // wait for text Edit Organization Title
  expect(await page.locator('text=Edit Organization Title')).toBeVisible();

  // check for the presence of the members page
  await page.goto(membersPageURL);

  // wait for page load completely
  await page.waitForTimeout(12000);
  // wait for text Team Members
  expect(await page.locator('text=Team Members')).toBeVisible();

  // check for the presence of the billing page
  await page.goto(billingPageURL);

  // wait for page load completely
  await page.waitForTimeout(12000);

  // wait for text Subscription
  expect(await page.locator('text=Subscription')).toBeVisible();
});
