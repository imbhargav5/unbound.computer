import { ArrowRight } from "lucide-react";
import { Link } from "@/components/intl-link";

type TitleBlockProps = {
  title: string;
  subtitle: string;
  icon?: React.ReactNode;
  section?: string;
  href?: string;
};

export default function TitleBlock({
  title,
  subtitle,
  icon,
  section,
  href = "#",
}: TitleBlockProps) {
  return (
    <div className="flex flex-1 flex-col space-y-4 md:items-center md:text-center">
      {section && (
        <Link href={href}>
          <div className="flex w-fit items-center gap-2 rounded-full border border-border bg-muted px-3 py-1 dark:border-none">
            {icon}
            <span className="font-medium text-md lg:text-base">{section}</span>
            <ArrowRight size={16} />
          </div>
        </Link>
      )}
      <h2 className="font-semibold text-2xl lg:text-4xl">{title}</h2>
      <p className="max-w-3xl text-muted-foreground leading-loose lg:text-xl lg:leading-relaxed">
        {subtitle}
      </p>
    </div>
  );
}
