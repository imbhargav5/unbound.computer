import { MoreVertical } from "lucide-react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { T } from "@/components/ui/typography-ui";
import { cn } from "@/utils/cn";

interface FeedbackPageHeadingProps {
  title: string;
  subTitle?: string;
  actions?: React.ReactNode;
  titleHref?: string;
  titleClassName?: string;
  subTitleClassName?: string;
  isLoading?: boolean;
  className?: string;
}

export function FeedbackPageHeading({
  title,
  subTitle,
  titleHref,
  actions,
  titleClassName,
  subTitleClassName,
  isLoading,
  className,
}: FeedbackPageHeadingProps) {
  const titleElement = (
    <T.H2
      className={cn(
        "",
        titleClassName,
        isLoading ? "text-4xl text-neutral-100 dark:text-neutral-800" : ""
      )}
      data-testid="page-heading-title"
    >
      {title}
    </T.H2>
  );

  const subTitleElement = subTitle && (
    <T.P
      className={cn(
        "text-lg text-muted-foreground leading-6",
        subTitleClassName
      )}
    >
      {subTitle}
    </T.P>
  );

  const wrappedTitleElement = titleHref ? (
    <Link href={titleHref}>{titleElement}</Link>
  ) : (
    <div className="w-full max-w-4xl">
      {titleElement}
      {subTitleElement}
    </div>
  );

  return (
    <div
      className={cn(
        "flex justify-between",
        isLoading ? "pointer-events-none animate-pulse" : "",
        className
      )}
    >
      <div className="min-w-0 flex-1">{wrappedTitleElement}</div>
      {actions && (
        <div className="ml-4 shrink-0">
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                className="h-8 w-8"
                data-testid="feedback-heading-actions-trigger"
                size="icon"
                variant="ghost"
              >
                <MoreVertical className="h-4 w-4" />
                <span className="sr-only">Open actions menu</span>
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-52">
              {actions}
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      )}
    </div>
  );
}
