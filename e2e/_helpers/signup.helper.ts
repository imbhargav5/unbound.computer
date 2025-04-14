import type { Page } from "@playwright/test";
import { expect, request } from "@playwright/test";
import {
  inbucketEmailMessageDetailSchema,
  inbucketEmailSchema,
} from "./inbucket-email-schema";

const INBUCKET_URL = `http://localhost:54324`;

/**
 * Message samples
 *
 * ----------\nMagic Link\n----------\n\nFollow this link to login:\n\nLog In ( http://127.0.0.1:54321/auth/v1/verify?token=pkce_8727a6aad33b430c0a5d01d92e5b2fca0481beda04dfa028a59a50b0&type=magiclink&redirect_to=http://localhost:3000/auth/callback )\n\nAlternatively, enter the code: 122956
 */

interface EmailConfirmation {
  token: string;
  url: string;
}

interface EmailMatcher {
  tokenMatcher: RegExp;
  urlMatcher: RegExp;
}

const matchers: EmailMatcher[] = [
  {
    tokenMatcher: /enter the code: ([0-9]+)/,
    urlMatcher: /Confirm your email address \( (.+) \)/,
  },
  {
    tokenMatcher: /enter the code: ([0-9]+)/,
    urlMatcher: /Log In \( (.+) \)/,
  },
];

function getTokenAndUrlFromEmailText(text: string): EmailConfirmation {
  for (const matcher of matchers) {
    const token = text.match(matcher.tokenMatcher)?.[1];
    const url = text.match(matcher.urlMatcher)?.[1];
    if (token && url) {
      return { token, url };
    }
  }
  throw new Error(
    "Email format unexpected - could not extract token and URL from email text",
  );
}

// eg endpoint: https://api.testmail.app/api/json?apikey=${APIKEY}&namespace=${NAMESPACE}&pretty=true
async function getConfirmEmail(username: string): Promise<EmailConfirmation> {
  const requestContext = await request.newContext();

  try {
    const response = await requestContext.get(
      `${INBUCKET_URL}/api/v1/search?query=${username}&limit=50`,
    );

    if (!response.ok()) {
      throw new Error(
        `Mailbox not found or not ready yet ${response.status()} for ${username}`,
      );
    }

    const emailResponse = await response.json().catch((error) => {
      throw new Error(`Failed to parse mailbox response: ${error.message}`);
    });

    const parsedEmailResponse = inbucketEmailSchema.parse(emailResponse);

    const messages = parsedEmailResponse.messages;

    // Get messages from the last 2 minutes, sorted by date
    const TWO_MINUTES = 2 * 60 * 1000;
    const now = new Date().getTime();
    const recentMessages = messages
      .filter((message) => {
        const messageDate = new Date(message.Created).getTime();
        return now - messageDate < TWO_MINUTES;
      })
      .sort(
        (a, b) => new Date(b.Created).getTime() - new Date(a.Created).getTime(),
      );

    if (recentMessages.length === 0) {
      throw new Error(`No recent messages found for user ${username}`);
    }

    // Try each recent message until we find one with the correct format
    for (const message of recentMessages) {
      try {
        const messageResponse = await requestContext.get(
          `${INBUCKET_URL}/api/v1/message/${message.ID}`,
        );

        if (!messageResponse.ok()) {
          continue; // Try next message if this one fails
        }

        const messageDetailsResponse = await messageResponse.json();
        const messageDetails = inbucketEmailMessageDetailSchema.parse(
          messageDetailsResponse,
        );

        try {
          // Try to extract token and URL from this message
          return getTokenAndUrlFromEmailText(messageDetails.Text);
        } catch (e) {
          // If this message doesn't match our format, try the next one
          continue;
        }
      } catch (e) {
        // If there's an error fetching this message, try the next one
        continue;
      }
    }

    throw new Error(`No valid confirmation emails found in the last 2 minutes`);
  } finally {
    await requestContext.dispose();
  }
}

export async function signupUserHelper({
  page,
  emailAddress,
  identifier,
}: {
  page: Page;
  emailAddress: string;
  identifier: string;
}) {
  await page.goto("/sign-up");

  const magicLinkButton = page.locator('button:has-text("Magic Link")');
  await magicLinkButton.waitFor({ state: "visible" });
  await magicLinkButton.click();

  const magicLinkForm = page.getByTestId("magic-link-form");
  await magicLinkForm.waitFor();

  const emailInput = magicLinkForm.locator("input");
  await emailInput.waitFor({ state: "visible" });
  await emailInput.fill(emailAddress);

  const submitButton = page.getByRole("button", {
    name: "Sign up with Magic Link",
  });
  await submitButton.waitFor({ state: "visible" });
  await submitButton.click();

  // Wait for confirmation message in the confirmation card
  const confirmationCard = page.getByTestId("email-confirmation-pending-card");
  await confirmationCard.waitFor({ state: "visible" });

  let confirmationUrl: string | null = null;

  await expect
    .poll(
      async () => {
        try {
          const result = await getConfirmEmail(identifier);
          confirmationUrl = result.url;
          return true;
        } catch (error) {
          console.log(
            `Polling for signup confirmation email: ${error.message}`,
          );
          return false;
        }
      },
      {
        message: `Waiting for signup confirmation email for ${identifier}`,
        timeout: 30000,
        intervals: [1000, 2000, 3000, 5000],
      },
    )
    .toBe(true);

  if (!confirmationUrl) {
    throw new Error(
      "Failed to get signup confirmation URL after successful poll",
    );
  }

  await page.goto(confirmationUrl);

  // Wait for redirect to onboarding
  await page.waitForURL(/\/[a-z]{2}\/onboarding/, {
    timeout: 10000,
    waitUntil: "networkidle",
  });
}
