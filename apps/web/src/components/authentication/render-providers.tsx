import * as SocialIcons from "@/components/authentication/icons-list";
import { Button } from "@/components/ui/button";
import type { SocialProvider } from "@/utils/zod-schemas/social-providers";

function capitalize(word: string) {
  const lower = word.toLowerCase();
  return word.charAt(0).toUpperCase() + lower.slice(1);
}

export const RenderProviders = ({
  providers,
  onProviderLoginRequested,
  isLoading,
}: {
  providers: SocialProvider[];
  onProviderLoginRequested: (provider: SocialProvider) => void;
  isLoading: boolean;
}) => (
  <div className="grid grid-cols-3 gap-3">
    {providers.map((provider) => {
      const AuthIcon = SocialIcons[provider];

      return (
        <Button
          className="h-11 bg-transparent font-medium"
          disabled={isLoading}
          key={provider}
          onClick={() => onProviderLoginRequested(provider)}
          variant="outline"
        >
          <div className="mr-2">
            <AuthIcon />
          </div>
          <span>{capitalize(provider)}</span>
        </Button>
      );
    })}
  </div>
);
