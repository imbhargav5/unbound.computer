/**
 * CLI Authentication Success Page
 *
 * Shown after successful OAuth authentication.
 * User can close this window and return to terminal.
 */
export default function CLIAuthSuccessPage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-green-50 to-blue-50 dark:from-gray-900 dark:to-gray-800">
      <div className="w-full max-w-md space-y-8 rounded-lg bg-white p-8 text-center shadow-lg dark:bg-gray-800">
        {/* Success Icon */}
        <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-green-100 dark:bg-green-900">
          <svg
            className="h-10 w-10 text-green-600 dark:text-green-400"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              d="M5 13l4 4L19 7"
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
            />
          </svg>
        </div>

        {/* Header */}
        <div>
          <h1 className="font-bold text-3xl text-gray-900 dark:text-white">
            Authentication Successful!
          </h1>
          <p className="mt-2 text-gray-600 text-sm dark:text-gray-400">
            Your CLI has been authenticated successfully.
          </p>
        </div>

        {/* Instructions */}
        <div className="rounded-md border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
          <p className="text-blue-800 text-sm dark:text-blue-400">
            You can now close this window and return to your terminal.
          </p>
        </div>

        {/* Auto-close Script */}
        <div className="pt-4">
          <p className="text-gray-500 text-xs dark:text-gray-400">
            This window will close automatically in a few seconds...
          </p>
        </div>
      </div>

      {/* Auto-close script */}
      <script
        dangerouslySetInnerHTML={{
          __html: `
            setTimeout(function() {
              window.close();
            }, 3000);
          `,
        }}
      />
    </div>
  );
}
