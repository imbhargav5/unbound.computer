import { useLoggedInUser } from "@/hooks/useLoggedInUser";
import posthog from "posthog-js";
import { PostHogProvider } from "posthog-js/react";
import { useEffect, useState, type ReactNode } from "react";
import { useGetIsMounted } from "rooks";

const useInitPostHog = () => {
  const user = useLoggedInUser();
  const [hasInit, setHasInit] = useState<boolean>(false);
  const getIsMounted = useGetIsMounted();
  useEffect(() => {
    posthog.init(process.env.NEXT_PUBLIC_POSTHOG_API_KEY, {
      loaded: () => {
        console.log("posthog loaded");
        if (getIsMounted()) {
          setHasInit(true);
        }
      },
      api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST,
    });
  }, [getIsMounted]);

  useEffect(() => {
    if (user && hasInit) {
      posthog.identify(user.id, {
        email: user.email,
        name: user.user_metadata.full_name,
      });
    }
  }, [user, hasInit]);
  return hasInit;
};

export default function PosthogProvider({ children }: { children: ReactNode }) {
  useInitPostHog();
  return <PostHogProvider client={posthog}>{children}</PostHogProvider>;
}
