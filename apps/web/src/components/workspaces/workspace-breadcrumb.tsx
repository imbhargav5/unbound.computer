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
import type { BreadcrumbSegment } from "./breadcrumb-config";

type WorkspaceBreadcrumbProps = {
  segments: BreadcrumbSegment[];
  basePath: string; // "" for solo, "/workspace/[slug]" for team
};

export function WorkspaceBreadcrumb({
  segments,
  basePath,
}: WorkspaceBreadcrumbProps) {
  // Always prepend "Workspace" as root linking to /home
  const allSegments: BreadcrumbSegment[] = [
    { label: "Workspace", href: `${basePath}/home` },
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
