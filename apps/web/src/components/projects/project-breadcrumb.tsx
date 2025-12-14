import { Fragment } from "react";
import { Link } from "@/components/intl-link";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import type { BreadcrumbSegment } from "@/components/workspaces/breadcrumb-config";

type ProjectBreadcrumbProps = {
  segments: BreadcrumbSegment[];
  basePath: string; // "/project/[slug]"
};

export function ProjectBreadcrumb({
  segments,
  basePath,
}: ProjectBreadcrumbProps) {
  // Always prepend "Project" as root linking to basePath
  const allSegments: BreadcrumbSegment[] = [
    { label: "Project", href: basePath },
    ...segments,
  ];

  return (
    <Breadcrumb>
      <BreadcrumbList>
        {allSegments.map((segment, index) => {
          const isLast = index === allSegments.length - 1;

          return (
            <Fragment key={segment.label}>
              {index > 0 && <BreadcrumbSeparator />}
              <BreadcrumbItem>
                {isLast || !segment.href ? (
                  <BreadcrumbPage>{segment.label}</BreadcrumbPage>
                ) : (
                  <BreadcrumbLink asChild>
                    <Link href={segment.href}>{segment.label}</Link>
                  </BreadcrumbLink>
                )}
              </BreadcrumbItem>
            </Fragment>
          );
        })}
      </BreadcrumbList>
    </Breadcrumb>
  );
}
