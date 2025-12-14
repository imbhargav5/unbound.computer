import { Fragment, Suspense } from "react";
import slugify from "slugify";
import urlJoin from "url-join";
import { Link } from "@/components/intl-link";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import type { BreadcrumbSegment } from "./breadcrumb-config";

type AdminBreadcrumbProps = {
  segments: BreadcrumbSegment[];
};

const BASE_PATH = "/app-admin";

export function AdminBreadcrumb({ segments }: AdminBreadcrumbProps) {
  // Always prepend "Admin" as root linking to /app-admin
  const allSegments: BreadcrumbSegment[] = [
    { label: "Admin", href: "/" },
    ...segments,
  ];

  return (
    <Breadcrumb>
      <BreadcrumbList>
        {allSegments.map((segment, index) => {
          const isLast = index === allSegments.length - 1;
          const href = segment.href
            ? segment.href.startsWith("/")
              ? `${urlJoin(BASE_PATH, segment.href)}`
              : segment.href
            : undefined;

          return (
            <Fragment key={`${segment.label}-${index}`}>
              {index > 0 && <BreadcrumbSeparator />}
              <BreadcrumbItem>
                {isLast || !href ? (
                  <BreadcrumbPage
                    data-testid={`admin-breadcrumb-${slugify(segment.label, { lower: true, strict: true, replacement: "-" })}`}
                  >
                    {segment.label}
                  </BreadcrumbPage>
                ) : (
                  <Suspense>
                    <BreadcrumbLink
                      asChild
                      data-testid={`admin-breadcrumb-${slugify(segment.label, { lower: true, strict: true, replacement: "-" })}`}
                    >
                      <Link href={href}>{segment.label}</Link>
                    </BreadcrumbLink>
                  </Suspense>
                )}
              </BreadcrumbItem>
            </Fragment>
          );
        })}
      </BreadcrumbList>
    </Breadcrumb>
  );
}
