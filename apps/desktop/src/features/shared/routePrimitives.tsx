import type { ReactNode } from "react";
import {
  Breadcrumb,
  BreadcrumbItem,
  BreadcrumbLink,
  BreadcrumbList,
  BreadcrumbPage,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

export interface DashboardBreadcrumbItem {
  label: string;
  onClick?: () => void;
}

export function DashboardBreadcrumbs({
  items,
}: {
  items: DashboardBreadcrumbItem[];
}) {
  return (
    <Breadcrumb>
      <BreadcrumbList>
        {items.map((item, index) => {
          const isCurrent = index === items.length - 1;

          return (
            <BreadcrumbItem key={`${item.label}-${index}`}>
              {item.onClick && !isCurrent ? (
                <BreadcrumbLink
                  className="cursor-pointer"
                  onClick={item.onClick}
                >
                  {item.label}
                </BreadcrumbLink>
              ) : (
                <BreadcrumbPage>{item.label}</BreadcrumbPage>
              )}
              {isCurrent ? null : <BreadcrumbSeparator />}
            </BreadcrumbItem>
          );
        })}
      </BreadcrumbList>
    </Breadcrumb>
  );
}

export function MetricCard({
  label,
  value,
}: {
  label: string;
  value: number | string;
}) {
  return (
    <Card size="sm">
      <CardContent className="flex flex-col gap-1">
        <span className="text-xs text-muted-foreground">{label}</span>
        <strong className="text-2xl font-semibold tracking-tight">
          {value}
        </strong>
      </CardContent>
    </Card>
  );
}

export function SummaryPill({
  label,
  value,
}: {
  label: string;
  value: number | string;
}) {
  return (
    <Badge variant="secondary" className="gap-1.5 px-2.5 py-1">
      <span className="text-muted-foreground">{label}</span>
      <strong className="font-medium">{value}</strong>
    </Badge>
  );
}

export function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="text-muted-foreground">{label}</span>
      <strong className="font-medium">{value}</strong>
    </div>
  );
}

export function RoutePlaceholder({
  body,
  title,
}: {
  body: string;
  title: string;
}) {
  return (
    <section className="flex-1 overflow-y-auto p-6">
      <div className="space-y-2">
        <DashboardBreadcrumbs items={[{ label: title }]} />
        <span className="text-xs font-medium uppercase tracking-wider text-muted-foreground">
          {title}
        </span>
        <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
        <p className="text-sm text-muted-foreground">{body}</p>
      </div>
    </section>
  );
}

export function BoardPlaceholderView({
  message,
  title,
}: {
  message: string;
  title: string;
}) {
  return (
    <section className="flex flex-1 items-center justify-center p-8">
      <div className="flex flex-col items-center gap-4 text-center">
        <BoardPlaceholderIcon />
        <div className="space-y-1">
          <h2 className="text-base font-semibold">{title}</h2>
          <p className="text-sm text-muted-foreground">{message}</p>
        </div>
      </div>
    </section>
  );
}

function BoardPlaceholderIcon() {
  return (
    <svg
      aria-hidden="true"
      className="size-12 text-muted-foreground/50"
      fill="none"
      viewBox="0 0 48 48"
    >
      <path
        d="M9 15.5h30v14a5.5 5.5 0 0 1-5.5 5.5H14.5A5.5 5.5 0 0 1 9 29.5v-14Z"
        rx="5.5"
        stroke="currentColor"
        strokeWidth="2.5"
      />
      <path
        d="M16 22h16"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="2.5"
      />
      <path
        d="M18.5 12.5h11"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth="2.5"
      />
    </svg>
  );
}

export function ProjectDialogSelectField({
  children,
  hint,
  label,
  onChange,
  value,
}: {
  children: ReactNode;
  hint: string;
  label: string;
  onChange: (value: string) => void;
  value: string;
}) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      <Select
        onValueChange={(v) => {
          if (v) onChange(v);
        }}
        value={value}
      >
        <SelectTrigger className="w-full">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>{children}</SelectContent>
      </Select>
      <p className="text-xs text-muted-foreground">{hint}</p>
    </div>
  );
}
