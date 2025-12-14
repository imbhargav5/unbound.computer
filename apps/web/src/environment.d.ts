declare global {
  namespace NodeJS {
    interface ProcessEnv {
      NEXT_PUBLIC_SUPABASE_URL: string;
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: string;
      SUPABASE_SECRET_KEY: string;
      SUPABASE_SERVICE_ROLE_KEY?: string;
      SUPABASE_JWT_SIGNING_KEY: string;
      NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY: string;
      STRIPE_SECRET_KEY: string;
      STRIPE_WEBHOOK_SECRET: string;
      NODE_ENV: "test" | "development" | "production";
      PORT?: string;
      NEXT_PUBLIC_VERCEL_URL?: string;
      NEXT_PUBLIC_SITE_URL?: string;
      ADMIN_EMAIL: string;
      NEXT_PUBLIC_SENTRY_DSN: string;
      NEXT_PUBLIC_POSTHOG_API_KEY: string;
      NEXT_PUBLIC_POSTHOG_APP_ID: string;
      NEXT_PUBLIC_POSTHOG_HOST: string;
      NEXT_PUBLIC_GA_ID: string;
      UNKEY_ROOT_KEY: string;
      UNKEY_API_ID: string;
      OPENAI_API_KEY?: string;
      USE_LOCAL_EMAIL?: string;
    }
  }
}

export {};
