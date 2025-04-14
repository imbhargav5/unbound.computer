import type { Page } from "@playwright/test";
import { expect, request } from "@playwright/test";
import {
  inbucketEmailMessageDetailSchema,
  inbucketEmailSchema,
} from "./inbucket-email-schema";

const INBUCKET_URL = `http://localhost:54324`;

interface EmailConfirmation {
  token: string;
  url: string;
}

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
          const tokenMatch = messageDetails.Text.match(
            /enter the code: ([0-9]+)/,
          );
          const urlMatch = messageDetails.Text.match(/Log In \( (.+) \)/);

          if (!tokenMatch?.[1] || !urlMatch?.[1]) {
            continue; // Try next message if format doesn't match
          }

          return {
            token: tokenMatch[1],
            url: urlMatch[1],
          };
        } catch (e) {
          // If this message doesn't match our format, try the next one
          continue;
        }
      } catch (e) {
        // If there's an error fetching this message, try the next one
        continue;
      }
    }

    throw new Error(
      `No valid login confirmation emails found in the last 2 minutes`,
    );
  } finally {
    await requestContext.dispose();
  }
}

export async function loginUserHelper({
  page,
  emailAddress,
}: {
  page: Page;
  emailAddress: string;
}) {
  await page.goto(`/login`);

  const magicLinkButton = page.locator('button:has-text("Magic Link")');
  await magicLinkButton.waitFor({ state: "visible" });
  await magicLinkButton.click();

  const magicLinkForm = page.getByTestId("magic-link-form");
  await magicLinkForm.waitFor();

  const emailInput = magicLinkForm.locator("input");
  await emailInput.waitFor({ state: "visible" });
  await emailInput.fill(emailAddress);

  const submitButton = magicLinkForm.locator("button");
  await submitButton.waitFor({ state: "visible" });
  await submitButton.click();

  await page.getByTestId("email-confirmation-pending-card").waitFor();

  const identifier = emailAddress.split("@")[0];
  let confirmationUrl: string | null = null;

  await expect
    .poll(
      async () => {
        try {
          const result = await getConfirmEmail(identifier);
          confirmationUrl = result.url;
          return true;
        } catch (error) {
          console.log(`Polling for email: ${error.message}`);
          return false;
        }
      },
      {
        message: `Waiting for confirmation email for ${identifier}`,
        timeout: 30000,
        intervals: [1000, 2000, 3000, 5000],
      },
    )
    .toBe(true);

  if (!confirmationUrl) {
    throw new Error("Failed to get confirmation URL after successful poll");
  }

  await page.goto(confirmationUrl);
}
