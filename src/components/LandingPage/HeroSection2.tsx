import { Button } from '@/components/ui/button';
import { T } from '@/components/ui/Typography';
import { ChevronRightIcon } from 'lucide-react';
import Image from 'next/image';
import Link from 'next/link';

type HeroSection2Props = {
  title: string;
  description: string;
  image?: string;
};

const HeroSection2 = ({ title, description, image }: HeroSection2Props) => {
  const imageSrc = image ? image : '/mockups/laptop.jpeg';
  return (
    <section className="w-full mx-auto">
      <div className="md:container mx-auto">
        <div className="px-4 md:px-4 w-full relative lg:px-24 flex flex-col items-center">
          <div className="flex flex-col items-center gap-y-6 max-w-5xl mb-16 ">
            <div className=" flex w-full flex-col gap-4 mt-24 md:items-center">
              <div className="flex gap-x-4 border group w-fit items-center pr-2 mb-2 border-border rounded-xl shadow-sm p-[2px]">
                <div className="flex items-center border border-border bg-muted rounded-lg shadow-sm px-2 py-[2px]">
                  <T.Small className="text-xs md:text-sm text-foreground dark:text-muted-foreground">
                    What's new?
                  </T.Small>
                </div>
                <div className="flex items-center">
                  <T.Small className="text-xs md:text-sm text-foreground dark:text-muted-foreground">
                    New Feature now available
                  </T.Small>
                  <ChevronRightIcon className="w-5 h-5 group-hover:translate-x-1 transition" />
                </div>
              </div>
              <h1 className="font-semibold text-4xl leading-[44px] sm:text-4xl md:text-5xl md:leading-[60px] xl:text-7xl 2xl:text-7xl xl:leading-[90px] max-w-2xl tracking-tighter text-foreground dark:text-card-foreground md:text-center">
                {title}
              </h1>
            </div>
            <p className="md:text-center text-foreground dark:text-muted-foreground text-xl leading-[30px] max-w-xl font-normal md:text-xl">
              {description}
            </p>
            <div className="flex flex-col w-full md:flex md:flex-row md:mx-auto items-center justify-center gap-y-3 md:gap-x-3 mr-0 mt-4">
              <Link href="/login" className="w-full md:w-fit">
                <Button
                  variant="default"
                  size="lg"
                  className="group w-full md:w-fit"
                  asChild
                >
                  <Link href="/login">
                    Log In
                    <svg
                      className="ml-2 -mr-1 w-5 h-5 group-hover:translate-x-1 transition"
                      fill="currentColor"
                      viewBox="0 0 20 20"
                      xmlns="http://www.w3.org/2000/svg"
                    >
                      <path
                        fillRule="evenodd"
                        d="M10.293 3.293a1 1 0 011.414 0l6 6a1 1 0 010 1.414l-6 6a1 1 0 01-1.414-1.414L14.586 11H3a1 1 0 110-2h11.586l-4.293-4.293a1 1 0 010-1.414z"
                        clipRule="evenodd"
                      />
                    </svg>
                  </Link>
                </Button>
              </Link>
              <Link href="/" className="w-full md:w-fit">
                <Button
                  variant="secondary"
                  size="lg"
                  className="px-4 group w-full md:w-fit"
                >
                  Learn More
                  <ChevronRightIcon className="ml-2 group-hover:translate-x-1 transition" />
                </Button>
              </Link>
            </div>
          </div>
        </div>
        <div className="mx-4 md:px-0 lg:mt-0 lg:col-span-5 rounded-lg overflow-hidden h-[320px] md:h-[640px] lg:flex">
          <Image
            src={imageSrc}
            width={1440}
            height={480}
            alt="mockup"
            className="object-cover object-center"
          />
        </div>
      </div>
    </section>
  );
};

export default HeroSection2;
