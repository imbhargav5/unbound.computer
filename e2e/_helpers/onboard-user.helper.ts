import { expect, type Page } from '@playwright/test';
import { matchPathAndExtractWorkspaceInfo } from './workspace.helper';

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

  const acceptTermsButton = termsDialog.getByRole('button', { name: /i accept the terms/i });
  await acceptTermsButton.click();

  // Profile Update
  const fullNameInput = page.getByRole('textbox', { name: 'Full Name' });
  await expect(fullNameInput).toBeVisible();
  await fullNameInput.fill(name);

  const saveProfileButton = page.getByRole('button', { name: 'Save Profile' });
  await saveProfileButton.click();

  // Workspace Creation (renamed from Organization)
  const workspaceNameInput = page.getByRole('textbox', { name: 'Workspace Name' });
  await expect(workspaceNameInput).toBeVisible();
  await workspaceNameInput.fill('My Workspace');

  const createWorkspaceButton = page.getByRole('button', { name: 'Create Workspace' });
  await createWorkspaceButton.click();


  const { workspaceId } = await matchPathAndExtractWorkspaceInfo({ page });
  expect(workspaceId).not.toBeNull();
}
