import { Check } from "lucide-react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { pricing } from "@/data/anon/pricing";
import { cn } from "@/lib/utils";

const Pricing = () => (
  <section
    className="mx-auto flex max-w-5xl flex-col items-center justify-center space-y-12 overflow-hidden px-6 py-20"
    id="pricing"
  >
    <div className="text-center">
      <p className="mb-4 font-medium text-sm text-white/40 uppercase tracking-widest">
        Pricing
      </p>
      <h2 className="mb-4 font-light text-3xl text-white lg:text-4xl">
        Simple, transparent pricing
      </h2>
      <p className="mx-auto max-w-xl text-white/40">
        Start free and scale as you grow. All plans include end-to-end
        encryption.
      </p>
    </div>

    <Tabs
      className="flex w-full flex-col items-center justify-center"
      defaultValue="monthly"
    >
      <TabsList className="mb-8 border border-white/10 bg-transparent">
        <TabsTrigger
          className="data-[state=active]:bg-white data-[state=active]:text-black"
          value="monthly"
        >
          Monthly
        </TabsTrigger>
        <TabsTrigger
          className="data-[state=active]:bg-white data-[state=active]:text-black"
          value="annual"
        >
          Annual
        </TabsTrigger>
      </TabsList>
      <TabsContent className="w-full" value="monthly">
        <div className="grid w-full grid-cols-1 gap-6 lg:grid-cols-3">
          {pricing.map((item, i) => (
            <PricingCard key={i} {...item} />
          ))}
        </div>
      </TabsContent>
      <TabsContent className="w-full" value="annual">
        <div className="grid w-full grid-cols-1 gap-6 lg:grid-cols-3">
          {pricing.map((item, i) => (
            <PricingCard key={i} {...item} price={item.annualPrice} />
          ))}
        </div>
      </TabsContent>
    </Tabs>
  </section>
);

const PricingCard = ({
  title,
  price,
  features,
  description,
  isHighlighted = false,
}: {
  title: string;
  price: string;
  features: string[];
  description: string;
  isHighlighted?: boolean;
}) => (
  <div
    className={cn(
      "flex h-full flex-col rounded-lg border border-white/10 p-6",
      isHighlighted && "border-white/30 bg-white/[0.02]"
    )}
  >
    <div className="mb-6 flex items-start justify-between">
      <div>
        <h3 className="mb-1 font-medium text-lg text-white">{title}</h3>
        <p className="text-sm text-white/40">{description}</p>
      </div>
      {isHighlighted && (
        <span className="rounded-full border border-white/20 px-3 py-1 text-white/70 text-xs">
          Popular
        </span>
      )}
    </div>

    <div className="mb-6">
      <span className="font-light text-4xl text-white">${price}</span>
      <span className="text-white/40">/month</span>
    </div>

    <Button
      asChild
      className={cn(
        "mb-6 w-full",
        isHighlighted
          ? "bg-white text-black hover:bg-white/90"
          : "border-white/20 bg-transparent hover:bg-white/5"
      )}
      variant={isHighlighted ? "default" : "outline"}
    >
      <Link href="/login">Get Started</Link>
    </Button>

    <div className="h-px w-full bg-white/10" />

    <ul className="mt-6 space-y-3">
      {features.map((feature, i) => (
        <li className="flex items-center gap-3 text-sm text-white/60" key={i}>
          <Check className="size-4 text-white/40" />
          {feature}
        </li>
      ))}
    </ul>
  </div>
);

export default Pricing;
