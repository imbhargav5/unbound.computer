import {
  computeSharedSecret,
  deriveKey,
  encryptSealed,
  fromBase64,
  generateKeyPair,
  parseWebSessionQRData,
  toBase64,
} from "@unbound/crypto";
import chalk from "chalk";
import ora from "ora";
import { credentials } from "../auth/index.js";
import { config } from "../config.js";
import { logger } from "../utils/index.js";

/**
 * Web Authorize command - authorize a web session by scanning QR code data
 *
 * This command is called after the user scans a QR code from the web interface.
 * It derives a session key from the Master Key and sends it encrypted to the web client.
 */
export async function webAuthorizeCommand(
  qrDataOrPrompt?: string
): Promise<void> {
  console.log(chalk.bold("\nAuthorize Web Session\n"));

  // Check if device is linked
  const isLinked = await credentials.isLinked();
  if (!isLinked) {
    console.log(chalk.red("Device not linked. Run 'unbound link' first."));
    process.exit(1);
  }

  // Check if device has Master Key
  const hasMasterKey = await credentials.hasMasterKey();
  if (!hasMasterKey) {
    console.log(
      chalk.red("Master Key not available. Pair with mobile app first.")
    );
    console.log(chalk.yellow("Run 'unbound pair' to receive the Master Key."));
    process.exit(1);
  }

  let qrData = qrDataOrPrompt;

  // If no QR data provided, prompt for it
  if (!qrData) {
    const readline = await import("readline");
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    qrData = await new Promise<string>((resolve) => {
      rl.question(
        chalk.blue("Paste the QR code data or web session URL: "),
        (answer) => {
          rl.close();
          resolve(answer.trim());
        }
      );
    });
  }

  if (!qrData) {
    console.log(chalk.red("No QR data provided."));
    process.exit(1);
  }

  const spinner = ora("Parsing QR code data...").start();

  try {
    // Parse the QR code data
    const parsed = parseWebSessionQRData(qrData);
    if (!parsed) {
      spinner.fail("Invalid QR code data");
      console.log(
        chalk.red(
          "\nThe QR code data is invalid or expired. Please scan a fresh QR code."
        )
      );
      process.exit(1);
    }

    spinner.text = "Validating session...";

    // Check expiration
    if (parsed.expiresAt < Date.now()) {
      spinner.fail("Session expired");
      console.log(
        chalk.red("\nThis web session has expired. Please start a new session.")
      );
      process.exit(1);
    }

    logger.debug(`Authorizing web session: ${parsed.sessionId.slice(0, 8)}...`);

    spinner.text = "Generating session key...";

    // Get Master Key and device info
    const masterKey = await credentials.getMasterKey();
    const deviceId = await credentials.getDeviceId();
    const apiKey = await credentials.getApiKey();

    if (!(masterKey && deviceId && apiKey)) {
      spinner.fail("Missing credentials");
      console.log(
        chalk.red("\nDevice credentials incomplete. Re-link device.")
      );
      process.exit(1);
    }

    // Generate ephemeral keypair for this authorization
    const responderKeyPair = generateKeyPair();

    // Compute shared secret with web client's public key
    const webPublicKey = fromBase64(parsed.publicKey);
    const sharedSecret = computeSharedSecret(
      responderKeyPair.privateKey,
      webPublicKey
    );

    // Derive web session key from Master Key
    const webSessionKey = deriveKey(
      masterKey,
      `unbound-web-session:${parsed.sessionId}`
    );

    // Derive encryption key from shared secret
    const encryptionKey = deriveKey(
      sharedSecret,
      `web-session-auth:${parsed.sessionId}`
    );

    // Encrypt the session key
    const encryptedSessionKey = encryptSealed(encryptionKey, webSessionKey);

    spinner.text = "Sending authorization...";

    // Call API to authorize the session
    const response = await fetch(
      `${config.apiUrl}/api/v1/web/sessions/${parsed.sessionId}/authorize`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          deviceId,
          encryptedSessionKey: toBase64(encryptedSessionKey),
          responderPublicKey: toBase64(responderKeyPair.publicKey),
        }),
      }
    );

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error ?? "Authorization failed");
    }

    spinner.succeed("Web session authorized!");

    console.log(chalk.green("\nThe web browser is now connected."));
    console.log(chalk.gray(`Session ID: ${parsed.sessionId.slice(0, 8)}...`));
    console.log(
      chalk.gray(
        `Expires: ${new Date(Date.now() + 24 * 60 * 60 * 1000).toLocaleString()}`
      )
    );
    console.log(
      chalk.yellow("\nTip: You can revoke this session from the web dashboard.")
    );
  } catch (error) {
    spinner.fail("Authorization failed");
    logger.error(`Web authorize error: ${error}`);
    console.log(chalk.red(`\nError: ${(error as Error).message}`));
    process.exit(1);
  }
}
