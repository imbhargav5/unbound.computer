import { test as setup } from '@playwright/test';
import { onboardUserHelper } from 'e2e/_helpers/onboard-user.helper';
import { signupUserHelper } from 'e2e/_helpers/signup.helper';


function getIdentifier(): string {
  return `maryjane` + Date.now().toString().slice(-4)
}

const authFile = 'playwright/.auth/user2.json';

setup('create account', async ({ page }) => {
  const identifier = getIdentifier()
  const emailAddress = `${identifier}@myapp.com`
  await signupUserHelper({ page, emailAddress, identifier });
  console.log('signup complete')

  await onboardUserHelper({ page, name: 'Mary Jane' });
  console.log('onboarding complete')
  await page.context().storageState({ path: authFile });
});
