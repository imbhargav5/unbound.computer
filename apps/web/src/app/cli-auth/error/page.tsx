"use client";

import { useSearchParams } from "next/navigation";

/**
 * CLI Authentication Error Page
 *
 * Shown when OAuth authentication fails.
 * Displays error details and instructions.
 */
export default function CLIAuthErrorPage() {
  const searchParams = useSearchParams();
  const error = searchParams.get("error");
  const description = searchParams.get("description");

  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-red-50 to-orange-50 dark:from-gray-900 dark:to-gray-800">
      <div className="w-full max-w-md space-y-8 rounded-lg bg-white p-8 text-center shadow-lg dark:bg-gray-800">
        {/* Error Icon */}
        <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-red-100 dark:bg-red-900">
          <svg
            className="h-10 w-10 text-red-600 dark:text-red-400"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              d="M6 18L18 6M6 6l12 12"
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
            />
          </svg>
        </div>

        {/* Header */}
        <div>
          <h1 className="font-bold text-3xl text-gray-900 dark:text-white">
            Authentication Failed
          </h1>
          <p className="mt-2 text-gray-600 text-sm dark:text-gray-400">
            There was a problem authenticating your CLI.
          </p>
        </div>

        {/* Error Details */}
        <div className="rounded-md border border-red-200 bg-red-50 p-4 text-left dark:border-red-800 dark:bg-red-900/20">
          <div className="space-y-2">
            {error && (
              <div>
                <p className="font-semibold text-red-900 text-xs dark:text-red-300">
                  Error Code:
                </p>
                <p className="font-mono text-red-800 text-sm dark:text-red-400">
                  {error}
                </p>
              </div>
            )}
            {description && (
              <div>
                <p className="font-semibold text-red-900 text-xs dark:text-red-300">
                  Details:
                </p>
                <p className="text-red-800 text-sm dark:text-red-400">
                  {description}
                </p>
              </div>
            )}
          </div>
        </div>

        {/* Instructions */}
        <div className="rounded-md border border-blue-200 bg-blue-50 p-4 dark:border-blue-800 dark:bg-blue-900/20">
          <p className="text-left text-blue-800 text-sm dark:text-blue-400">
            <strong>What to do next:</strong>
            <br />
            1. Close this window and return to your terminal
            <br />
            2. Run{" "}
            <code className="rounded bg-blue-100 px-1 dark:bg-blue-900">
              unbound login
            </code>{" "}
            again
            <br />
            3. If the problem persists, contact support
          </p>
        </div>

        {/* Close Button */}
        <button
          className="w-full rounded-md border border-gray-300 bg-white px-4 py-2 font-medium text-gray-700 text-sm shadow-sm hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 dark:border-gray-600 dark:bg-gray-700 dark:text-gray-200 dark:hover:bg-gray-600"
          onClick={() => window.close()}
          type="button"
        >
          Close Window
        </button>
      </div>
    </div>
  );
}
