import { Terminal } from "lucide-react";
import Icons from "../icons";

export default function Quotation() {
  return (
    <section className="flex flex-col items-center justify-center space-y-2 bg-muted/40 p-16 lg:p-24">
      <div>
        <Icons.quote />
      </div>
      <h2 className="max-w-4xl text-center font-medium text-2xl lg:text-4xl">
        Start Claude Code from your couch, review diffs on the train, merge PRs
        from anywhere. Your dev machine stays secure at home.
      </h2>
      <div className="flex items-center gap-3 pt-3">
        <div className="flex size-7 items-center justify-center rounded-full bg-secondary">
          <Terminal className="text-muted-foreground" size={14} />
        </div>
        <div className="flex items-center gap-2">
          <p className="font-medium text-muted-foreground text-sm">
            unbound.computer
          </p>
          <div className="h-4 w-[2px] bg-slate-400" />
          <p className="font-light text-muted-foreground text-sm">
            Code from anywhere
          </p>
        </div>
      </div>
    </section>
  );
}
