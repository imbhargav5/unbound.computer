import { ArrowRight, ChevronRight, Sparkles } from "lucide-react";
import Image from "next/image";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import { AvatarCirclesDemo } from "./avatar-circles-demo";

export default async function HeroSection() {
  return (
    <section className="mx-auto max-w-5xl px-6 py-10 text-left lg:py-20 lg:text-center">
      <div className="flex w-full flex-col gap-10">
        <div className="flex flex-1 flex-col space-y-4 lg:items-center">
          <Link href={"#"}>
            <div className="flex w-fit items-center gap-2 rounded-full border border-border bg-secondary px-3 py-1 dark:border-none">
              <Sparkles size={16} />
              <span className="font-medium text-md lg:text-base">
                Introducing
              </span>
              <ArrowRight size={16} />
            </div>
          </Link>
          <h1 className="max-w-xl font-thin text-3xl lg:text-5xl">
            Fast typesafe starterkit <br />
            for <em>vibecoders</em>
          </h1>
          <p className="max-w-4xl text-muted-foreground leading-loose lg:text-lg lg:leading-relaxed">
            Welcome to Nextbase Ultimate Landing Page: Your Gateway to
            Innovation. Discover the Future of Excellence and Elevate Your
            Experience.
          </p>
          <div className="flex w-full flex-col gap-4 pt-4 sm:flex-row sm:justify-center">
            <Button asChild className="w-full sm:w-auto sm:min-w-32">
              <Link href={"/login"}>
                Log In
                <ArrowRight className="ml-2" size={16} />
              </Link>
            </Button>
            <Button
              className="w-full sm:w-auto sm:min-w-32"
              variant={"secondary"}
            >
              Learn More
              <ChevronRight className="ml-2" size={16} />
            </Button>
          </div>
        </div>
        <div className="flex items-center justify-center">
          <AvatarCirclesDemo />
        </div>
        <div className="relative aspect-21/9 w-full overflow-hidden rounded-md border-2 border-border shadow-xs">
          <Image
            alt="Hero Image"
            className="object-cover"
            fill
            priority
            sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
            src="/images/hero.jpeg"
          />
        </div>
      </div>
    </section>
  );
}
