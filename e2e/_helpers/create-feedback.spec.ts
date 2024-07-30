// @src/e2e/_helpers/create-feedback.spec.ts
import { type Page } from '@playwright/test';

export async function createFeedbackHelper(page: Page) {
  await page.goto('/dashboard');

  // Wait for network idle state
  await page.waitForLoadState('networkidle');

  // Use Promise.all to perform actions concurrently
  await Promise.all([
    page.click('div[data-testid="user-nav-avatar"]'),
    page.locator('[data-testid="feedback-link"]').waitFor({ state: 'attached' }),
  ]);

  await page.click('[data-testid="feedback-link"]');

  // Use locator for the form and its fields
  const form = page.locator('[data-testid="give-feedback-form"]');
  await form.waitFor({ state: 'visible' });

  await form.locator('[name="title"]').fill('Test title');
  await form.locator('[name="content"]').fill('Test content');

  // Use Promise.all for the final click and navigation
  await Promise.all([
    page.click('[data-testid="submit-feedback-button"]'),
  ]);
}
