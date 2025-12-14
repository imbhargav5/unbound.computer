import { CheckCircle2Icon, DollarSign } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { pricing } from "@/data/anon/pricing";
import { cn } from "@/lib/utils";
import TitleBlock from "../title-block";

const Pricing = () => (
  <section className="mx-auto flex max-w-6xl flex-col items-center justify-center space-y-10 overflow-hidden px-6 py-16">
    <TitleBlock
      icon={<DollarSign size={16} />}
      section="Pricing"
      subtitle="CI/CD streamlines feature delivery, scalable infrastructure ensures global edge optimization and app monitoring capabilities for peak site performance."
      title="Quality without any compromise"
    />

    <Tabs
      className="flex w-full flex-col items-center justify-center"
      defaultValue="monthly"
    >
      <TabsList className="mb-6 w-full max-w-80">
        <TabsTrigger className="w-full" value="monthly">
          Monthly
        </TabsTrigger>
        <TabsTrigger className="w-full" value="annual">
          Annual
        </TabsTrigger>
      </TabsList>
      <TabsContent className="w-full" value="monthly">
        <div className="grid w-full grid-cols-1 gap-8 lg:grid-cols-3">
          {pricing.map((item, i) => (
            <PricingCard key={i} {...item} />
          ))}
        </div>
      </TabsContent>
      <TabsContent className="w-full" value="annual">
        <div className="grid w-full grid-cols-1 gap-8 lg:grid-cols-3">
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
  <Card className={cn(`${isHighlighted ? "bg-secondary" : ""} , h-fit`)}>
    <CardHeader className="space-y-1 p-4">
      <div className="flex items-start justify-between">
        <div>
          <CardTitle className="font-bold text-xl">{title}</CardTitle>
          <CardDescription className="text-base">{description}</CardDescription>
        </div>
        {isHighlighted && <Badge>Most Popular</Badge>}
      </div>
      <h3 className="py-3 font-bold text-4xl tracking-tighter">${price}</h3>
      <Button className="w-full">Get Started</Button>
    </CardHeader>

    <CardContent className="p-4">
      <div className="h-[1px] w-full bg-slate-200 dark:bg-slate-500" />
      <ul className="space-y-3 pt-10">
        {features.map((feature, i) => (
          <li className="flex items-center" key={i}>
            <CheckCircle2Icon size={16} />
            <span className="ml-2 font-medium text-sm">{feature}</span>
          </li>
        ))}
      </ul>
    </CardContent>
  </Card>
);

export default Pricing;
