import { Fragment } from "react";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import type { WorkspaceBreadcrumbSubPathSegment } from "./breadcrumb-config";
import urlJoin from "url-join";
import Link from "next/link";

type WorkspaceBreadcrumbProps = {
  segments: WorkspaceBreadcrumbSubPathSegment[];
  workspaceSlug: string;
};

export function WorkspaceBreadcrumbLink({
  workspaceSlug,
  segment,
}: {
  workspaceSlug: string;
  segment: WorkspaceBreadcrumbSubPathSegment;
}) {
  const href = urlJoin(`/workspace/${workspaceSlug}`, segment.subPath ?? "");
  return <Link href={href}>{segment.label}</Link>;
}


export function WorkspaceBreadcrumb({ segments, workspaceSlug }: WorkspaceBreadcrumbProps) {
  // Always prepend "Workspace" as root linking to /home
  const allSegments: WorkspaceBreadcrumbSubPathSegment[] = [
    { label: "Workspace", subPath: "/home" },
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
                {isLast || !segment.subPath ? (
                  <BreadcrumbPage>{segment.label}</BreadcrumbPage>
                ) : (
                  <BreadcrumbLink asChild>
                    <WorkspaceBreadcrumbLink workspaceSlug={workspaceSlug} segment={segment} />
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
