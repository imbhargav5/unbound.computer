import { Laptop, Smartphone, Terminal } from "lucide-react";

const steps = [
  {
    number: "01",
    title: "Install macOS App",
    description: "Install the Unbound app on your Mac",
    icon: Laptop,
  },
  {
    number: "02",
    title: "Install iOS App",
    description: "Install the Unbound app on your iPhone",
    icon: Smartphone,
  },
  {
    number: "03",
    title: "Use Claude Anywhere",
    description: "Start and control Claude Code sessions from anywhere",
    icon: Terminal,
  },
];

export default function HowItWorks() {
  return (
    <section className="mx-auto max-w-5xl px-6 py-20">
      <div className="mb-16 text-center">
        <p className="mb-4 font-medium text-sm text-white/40 uppercase tracking-widest">
          How it works
        </p>
        <h2 className="font-light text-3xl text-white lg:text-4xl">
          Three steps to freedom
        </h2>
      </div>

      <div className="relative">
        {/* Connecting line */}
        <div className="-translate-x-1/2 absolute top-12 left-1/2 hidden h-[2px] w-[60%] bg-gradient-to-r from-transparent via-white/10 to-transparent lg:block" />

        <div className="grid gap-12 lg:grid-cols-3 lg:gap-8">
          {steps.map((step) => (
            <div
              className="relative flex flex-col items-center text-center"
              key={step.number}
            >
              {/* Step number */}
              <div className="mb-6 flex size-20 items-center justify-center rounded-full border border-white/10 bg-white/[0.02]">
                <step.icon className="size-8 text-white/70" strokeWidth={1.5} />
              </div>

              {/* Number badge */}
              <span className="-top-2 absolute right-1/2 translate-x-12 font-mono text-white/30 text-xs">
                {step.number}
              </span>

              {/* Content */}
              <h3 className="mb-2 font-medium text-white text-xl">
                {step.title}
              </h3>
              <p className="mb-4 text-white/40">{step.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
