import {
  createServer,
  type IncomingMessage,
  type ServerResponse,
} from "node:http";
import open from "open";
import { config } from "../config.js";
import { logger } from "../utils/index.js";

/**
 * OAuth callback result
 */
interface OAuthResult {
  success: boolean;
  accessToken?: string;
  refreshToken?: string;
  userId?: string;
  error?: string;
}

/**
 * Start OAuth flow by opening browser and waiting for callback
 */
export async function startOAuthFlow(): Promise<OAuthResult> {
  return new Promise((resolve) => {
    const port = config.oauthCallbackPort;

    // Create a simple HTTP server to receive the OAuth callback
    const server = createServer((req: IncomingMessage, res: ServerResponse) => {
      const url = new URL(req.url || "/", `http://localhost:${port}`);

      if (url.pathname === "/callback") {
        const accessToken = url.searchParams.get("access_token");
        const refreshToken = url.searchParams.get("refresh_token");
        const userId = url.searchParams.get("user_id");
        const error = url.searchParams.get("error");

        // Send response to browser
        res.writeHead(200, { "Content-Type": "text/html" });

        if (error) {
          res.end(`
            <!DOCTYPE html>
            <html>
              <head><title>Unbound - Authentication Failed</title></head>
              <body style="font-family: system-ui; text-align: center; padding: 50px;">
                <h1>Authentication Failed</h1>
                <p>Error: ${error}</p>
                <p>You can close this window and try again.</p>
              </body>
            </html>
          `);
          resolve({ success: false, error });
        } else if (accessToken && userId) {
          res.end(`
            <!DOCTYPE html>
            <html>
              <head><title>Unbound - Authentication Successful</title></head>
              <body style="font-family: system-ui; text-align: center; padding: 50px;">
                <h1>Authentication Successful!</h1>
                <p>You can close this window and return to the terminal.</p>
                <script>window.close();</script>
              </body>
            </html>
          `);
          resolve({
            success: true,
            accessToken,
            refreshToken: refreshToken || undefined,
            userId,
          });
        } else {
          res.end(`
            <!DOCTYPE html>
            <html>
              <head><title>Unbound - Authentication Error</title></head>
              <body style="font-family: system-ui; text-align: center; padding: 50px;">
                <h1>Authentication Error</h1>
                <p>Missing required parameters.</p>
                <p>You can close this window and try again.</p>
              </body>
            </html>
          `);
          resolve({ success: false, error: "Missing required parameters" });
        }

        // Close server after handling callback
        setTimeout(() => {
          server.close();
        }, 1000);
      } else {
        res.writeHead(404);
        res.end("Not found");
      }
    });

    server.listen(port, () => {
      logger.debug(`OAuth callback server listening on port ${port}`);

      // Build the OAuth URL
      const callbackUrl = `http://localhost:${port}/callback`;
      const authUrl = `${config.apiUrl}/auth/cli?callback=${encodeURIComponent(callbackUrl)}`;

      logger.debug(`Opening browser: ${authUrl}`);

      // Open browser
      open(authUrl).catch((err) => {
        logger.error(`Failed to open browser: ${err.message}`);
        resolve({ success: false, error: "Failed to open browser" });
        server.close();
      });
    });

    // Timeout after configured time
    setTimeout(() => {
      server.close();
      resolve({ success: false, error: "OAuth timeout" });
    }, config.oauthTimeout);
  });
}
