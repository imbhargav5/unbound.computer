export function ChatBubblesIllustration() {
  return (
    <>
      {/* Gradient overlay */}
      <div className="absolute inset-0 bg-gradient-to-br from-muted to-muted/80" />

      {/* Chat-like UI illustration */}
      <div className="relative z-10 flex flex-col items-center gap-8 p-12">
        <div className="w-full max-w-sm space-y-4">
          {/* Message bubble - left */}
          <div className="flex justify-start">
            <div className="rounded-2xl rounded-tl-sm border border-border/50 bg-background px-5 py-3 shadow-sm">
              <p className="text-foreground text-sm">Welcome back</p>
            </div>
          </div>

          {/* Message bubble - right */}
          <div className="flex justify-end">
            <div className="rounded-2xl rounded-tr-sm bg-primary px-5 py-3 shadow-sm">
              <p className="text-primary-foreground text-sm">Ready to build</p>
            </div>
          </div>

          {/* Typing indicator bubble */}
          <div className="flex justify-start">
            <div className="rounded-2xl rounded-tl-sm border border-border/50 bg-background px-5 py-3 shadow-sm">
              <div className="flex items-center gap-2">
                <div className="flex gap-1">
                  <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-muted-foreground/40" />
                  <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-muted-foreground/40 delay-100" />
                  <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-muted-foreground/40 delay-200" />
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Decorative icons */}
        <div className="mt-8 flex items-center gap-3">
          <div className="flex h-12 w-12 items-center justify-center rounded-xl border border-border/50 bg-background/80 shadow-sm">
            <svg
              className="h-6 w-6 text-muted-foreground"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                d="M13 10V3L4 14h7v7l9-11h-7z"
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1.5}
              />
            </svg>
          </div>
          <div className="flex h-12 w-12 items-center justify-center rounded-xl border border-border/50 bg-background/80 shadow-sm">
            <svg
              className="h-6 w-6 text-muted-foreground"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1.5}
              />
            </svg>
          </div>
          <div className="flex h-12 w-12 items-center justify-center rounded-xl border border-border/50 bg-background/80 shadow-sm">
            <svg
              className="h-6 w-6 text-muted-foreground"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1.5}
              />
            </svg>
          </div>
        </div>
      </div>

      {/* Background dot pattern */}
      <div
        className="absolute inset-0 opacity-[0.03]"
        style={{
          backgroundImage: `url("data:image/svg+xml,%3Csvg width='60' height='60' viewBox='0 0 60 60' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' fillRule='evenodd'%3E%3Cg fill='%23000000' fillOpacity='1'%3E%3Cpath d='M36 34v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zm0-30V0h-2v4h-4v2h4v4h2V6h4V4h-4zM6 34v-4H4v4H0v2h4v4h2v-4h4v-2H6zM6 4V0H4v4H0v2h4v4h2V6h4V4H6z'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E")`,
        }}
      />
    </>
  );
}
