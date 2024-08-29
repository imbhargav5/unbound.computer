import { expect, type Page } from '@playwright/test';
import { extractOrganizationIdFromUrl } from './dashboard-default-organization-id.helper';

export async function onboardUserHelper({
  page,
  name,
}: {
  page: Page;
  name: string;
}) {
  // Terms Acceptance
  const viewTermsButton = page.getByRole('button', { name: 'View Terms' });
  await viewTermsButton.click();

  const termsDialog = page.getByRole('dialog');
  await expect(termsDialog).toBeVisible();

  const acceptTermsButton = termsDialog.getByRole('button', { name: 'Accept Terms' });
  await acceptTermsButton.click();


  // Profile Update
  const fullNameInput = page.getByRole('textbox', { name: 'Full Name' });
  await expect(fullNameInput).toBeVisible();
  await fullNameInput.fill(name);

  const saveProfileButton = page.getByRole('button', { name: 'Save Profile' });
  await saveProfileButton.click();


  // Organization Creation
  const orgTitleInput = page.getByRole('textbox', { name: 'Organization Name' });
  await expect(orgTitleInput).toBeVisible();
  await orgTitleInput.fill('My Organization');



  const createOrgButton = page.getByRole('button', { name: 'Create Organization' });
  await createOrgButton.click();

  // data-testid onboarding-complete should be visible
  const onboardingComplete = page.getByTestId('onboarding-complete');
  await expect(onboardingComplete).toBeDefined();


  const defaultOrganizationId = await extractOrganizationIdFromUrl({ page });
  expect(defaultOrganizationId).not.toBeNull();
}
