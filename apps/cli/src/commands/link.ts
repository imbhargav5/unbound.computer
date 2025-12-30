import { generateKeyPair, toBase64 } from "@unbound/crypto";
import { generateDeviceId, generateFingerprint } from "@unbound/identity";
import chalk from "chalk";
import ora from "ora";
import { credentials, startOAuthFlow } from "../auth/index.js";
import { config, deviceInfo } from "../config.js";
import { installDaemonService, logger } from "../utils/index.js";

/**
 * Link command - authenticate and register device
 */
export async function linkCommand(): Promise<void> {
  console.log(chalk.bold("\nUnbound CLI Setup\n"));

  // Check if already linked
  const isLinked = await credentials.isLinked();
  if (isLinked) {
    console.log(
      chalk.yellow(
        "This device is already linked. Run 'unbound unlink' first to re-link."
      )
    );
    return;
  }

  // Step 1: OAuth authentication
  console.log(chalk.blue("Step 1: Authentication"));
  console.log("Opening browser for authentication...\n");

  const oauthResult = await startOAuthFlow();

  if (!(oauthResult.success && oauthResult.accessToken && oauthResult.userId)) {
    console.log(chalk.red(`\nAuthentication failed: ${oauthResult.error}`));
    process.exit(1);
  }

  console.log(chalk.green("Authentication successful!\n"));

  // Step 2: Generate device identity
  console.log(chalk.blue("Step 2: Registering device"));
  const spinner = ora("Generating device identity...").start();

  try {
    // Determine device type
    const deviceType = deviceInfo.isMac
      ? "mac"
      : deviceInfo.isLinux
        ? "linux"
        : deviceInfo.isWindows
          ? "windows"
          : "linux";

    // Generate device identity components
    const deviceId = generateDeviceId();
    const fingerprint = generateFingerprint();
    const keyPair = generateKeyPair();
    const publicKeyBase64 = toBase64(keyPair.publicKey);

    spinner.text = "Registering with server...";

    // Register device with API
    const response = await fetch(`${config.apiUrl}/api/v1/cli/generate-token`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${oauthResult.accessToken}`,
      },
      body: JSON.stringify({
        deviceId,
        deviceName: deviceInfo.hostname,
        deviceType,
        hostname: deviceInfo.hostname,
        fingerprint,
        publicKey: publicKeyBase64,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`Registration failed: ${errorText}`);
    }

    const result = (await response.json()) as {
      apiKey: string;
      deviceId: string;
    };

    spinner.text = "Storing credentials securely...";

    // Store credentials
    await credentials.init();
    await credentials.setApiKey(result.apiKey);
    await credentials.setDeviceId(result.deviceId);
    await credentials.setDeviceName(deviceInfo.hostname);
    await credentials.setUserId(oauthResult.userId);
    await credentials.setLinkedAt(new Date());

    // Store device private key securely in keychain
    await credentials.setDevicePrivateKey(keyPair.privateKey);

    spinner.succeed("Device registered successfully!");

    // Step 3: Install daemon service
    console.log(chalk.blue("\nStep 3: Installing daemon service"));
    const daemonSpinner = ora("Installing background service...").start();

    try {
      await installDaemonService();
      daemonSpinner.succeed("Daemon service installed and started!");
    } catch (daemonError) {
      daemonSpinner.warn("Could not install daemon service automatically");
      logger.debug(`Daemon install error: ${daemonError}`);
      console.log(chalk.yellow("You can start the daemon manually with:"));
      console.log(chalk.cyan("  unbound start\n"));
    }

    // Step 4: Show next steps
    console.log(chalk.blue("\nStep 4: Mobile Pairing (Optional)"));
    console.log("To pair with the mobile app, run:");
    console.log(chalk.cyan("  unbound pair\n"));

    console.log(chalk.blue("Step 5: Register Projects"));
    console.log("Navigate to a git repository and run:");
    console.log(chalk.cyan("  unbound register\n"));

    console.log(chalk.green("Setup complete!"));
    console.log(`Logged in as user: ${chalk.cyan(oauthResult.userId)}`);
    console.log(`Device: ${chalk.cyan(deviceInfo.hostname)}`);
  } catch (error) {
    spinner.fail("Registration failed");
    logger.error(`Link error: ${error}`);
    console.log(chalk.red(`\nError: ${(error as Error).message}`));
    process.exit(1);
  }
}
