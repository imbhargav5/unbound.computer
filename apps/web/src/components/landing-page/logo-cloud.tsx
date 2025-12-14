import Image from "next/image";
import { logos } from "@/data/anon/logos";
import { Marquee } from "../magicui/marquee";

export default function LogoCloud() {
  return (
    <section className="mx-auto flex max-w-6xl items-center justify-center overflow-hidden text-center">
      <div className="space-y-2">
        <p className="font-semibold text-gray-500 text-xl">
          Trusted by 150+ Companies
        </p>
        <div className="w-full">
          <div className="mx-auto w-full px-4 md:px-8">
            <div
              className="group relative mt-6 flex gap-6 overflow-hidden p-2"
              style={{
                maskImage:
                  "linear-gradient(to left, transparent 0%, black 20%, black 80%, transparent 95%)",
              }}
            >
              <Marquee pauseOnHover>
                {logos.map((logo, key) => (
                  <a href={logo.website} key={key} target="_blank">
                    <Image
                      alt={`${logo.name}`}
                      className="px-2 brightness-200 grayscale-[100%] invert-[50%] dark:grayscale-0 dark:invert-[50%]"
                      height={40}
                      src={logo.url}
                      width={112}
                    />
                  </a>
                ))}
              </Marquee>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
