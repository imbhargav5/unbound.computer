import { ArrowRight, Terminal } from "lucide-react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import TitleBlock from "../title-block";

export default function CTA() {
  return (
    <div className="flex flex-col items-center justify-center space-y-6 bg-muted/40 px-6 py-16">
      <TitleBlock
        icon={<Terminal size={16} />}
        section="Get Started"
        subtitle="Install the CLI, pair your mobile device, and start coding from anywhere. Your development machine stays secure while you work on the go."
        title="Ready to go unbound?"
      />
      <div className="flex flex-col gap-4 sm:flex-row">
        <Button asChild className="w-full px-6 sm:w-auto sm:min-w-32">
          <Link href="/sign-up">
            Create Account
            <ArrowRight className="ml-2" size={16} />
          </Link>
        </Button>
        <Button
          asChild
          className="w-full px-6 sm:w-auto sm:min-w-32"
          variant="outline"
        >
          <Link href="/docs">View Documentation</Link>
        </Button>
      </div>
    </div>
  );
}
