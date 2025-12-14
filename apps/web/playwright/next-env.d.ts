declare module "@next/env" {
  export function loadEnvConfig(
    dir: string,
    dev?: boolean,
    log?: { info: (...args: unknown[]) => void; error: (...args: unknown[]) => void }
  ): {
    combinedEnv: Record<string, string>;
    loadedEnvFiles: Array<{ path: string; contents: string }>;
  };
}






