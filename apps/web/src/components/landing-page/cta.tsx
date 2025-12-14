import { Sailboat } from "lucide-react";
import { Button } from "@/components/ui/button";
import TitleBlock from "../title-block";

export default function CTA() {
  return (
    <div className="flex flex-col items-center justify-center space-y-6 bg-muted/40 px-6 py-16">
      <TitleBlock
        icon={<Sailboat size={16} />}
        section="Start you journey"
        subtitle="CI/CD streamlines feature delivery, scalable infrastructure ensures global edge optimization and app monitoring capabilities for peak site performance."
        title="Ready to move with ultimate?"
      />
      <Button className="w-full px-6 sm:w-auto sm:min-w-32">Get Started</Button>
    </div>
  );
}
