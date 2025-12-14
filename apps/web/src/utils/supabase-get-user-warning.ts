const KNOWN_WARNING_MATCHERS = [
  [
    "Using the user object as returned from supabase.auth.getSession()",
    "Use supabase.auth.getUser() instead",
  ],
];

const shouldIgnoreWarning = (warning: any) => {
  if (typeof warning !== "string") {
    return false;
  }
  return KNOWN_WARNING_MATCHERS.some(([matcher, _]) =>
    warning.includes(matcher)
  );
};

const originalConsoleWarn = console.warn;
const originalConsoleError = console.error;
const originalConsoleLog = console.log;

function enableWarningByPass() {
  console.warn = (warning: any) => {
    if (shouldIgnoreWarning(warning)) {
      return;
    }
    originalConsoleWarn(warning);
  };
  console.error = (error: any) => {
    if (shouldIgnoreWarning(error)) {
      return;
    }
    originalConsoleError(error);
  };
  console.log = (log: any) => {
    if (shouldIgnoreWarning(log)) {
      return;
    }
    originalConsoleLog(log);
  };
  return {
    resetConsole: () => {
      console.warn = originalConsoleWarn;
      console.error = originalConsoleError;
      console.log = originalConsoleLog;
    },
  };
}

export { enableWarningByPass };
