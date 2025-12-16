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
import type { WorkspaceBreadcrumbSubPathSegment } from "@/components/workspaces/breadcrumb-config";
import urlJoin from "url-join";

type ProjectBreadcrumbProps = {
  segments: WorkspaceBreadcrumbSubPathSegment[];
  projectSlug: string;
};

export function ProjectBreadcrumbLink({
  projectSlug,
  segment,
}: {
  projectSlug: string;
  segment: WorkspaceBreadcrumbSubPathSegment;
}) {
  const href = urlJoin(`/project/${projectSlug}`, segment.subPath ?? "");
  return <Link href={href}>{segment.label}</Link>;
}


export function ProjectBreadcrumb({
  segments,
  projectSlug,
}: ProjectBreadcrumbProps) {
  // Always prepend "Project" as root linking to basePath
  const allSegments: WorkspaceBreadcrumbSubPathSegment[] = [
    { label: "Project", subPath: "/" },
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
                    <ProjectBreadcrumbLink projectSlug={projectSlug} segment={segment} />
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
