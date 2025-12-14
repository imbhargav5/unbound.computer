import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";

export function ExternalNavigationCTAButton({
  isLoggedIn = false,
  isLoading,
}: {
  isLoggedIn?: boolean;
  isLoading?: boolean;
}) {
  const href = isLoggedIn ? "/dashboard" : "/login";
  const text = isLoggedIn ? "Dashboard" : "Log In";
  return (
    <Link className="w-full" href={href}>
      <Button className="group w-full" size="default" variant="default">
        {isLoading ? (
          "Please wait..."
        ) : (
          <>
            {text}
            <svg
              className="-mr-1 ml-2 h-5 w-5 transition group-hover:translate-x-1"
              fill="currentColor"
              viewBox="0 0 20 20"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path
                clipRule="evenodd"
                d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z"
                fillRule="evenodd"
              />
            </svg>
          </>
        )}
      </Button>
    </Link>
  );
}
