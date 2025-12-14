import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import Icons from "../icons";

export default function Quotation() {
  return (
    <section className="flex flex-col items-center justify-center space-y-2 bg-muted/40 p-16 lg:p-24">
      <div>
        <Icons.quote />
      </div>
      <h2 className="max-w-4xl text-center font-medium text-2xl lg:text-4xl">
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Integer nec
        odio. Praesent libero.
      </h2>
      <div className="flex items-center gap-3 pt-3">
        <Avatar className="size-7">
          <AvatarImage alt="@shadcn" src="/images/quote.png" />
          <AvatarFallback>CN</AvatarFallback>
        </Avatar>
        <div className="flex items-center gap-2">
          <p className="font-medium text-muted-foreground text-sm">
            Mark Zuckerburg
          </p>
          <div className="h-4 w-[2px] bg-slate-400" />
          <p className="font-light text-muted-foreground text-sm">
            CEO, Facebook
          </p>
        </div>
      </div>
    </section>
  );
}
