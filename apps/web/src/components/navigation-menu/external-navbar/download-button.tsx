import { Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { macOsDownloadUrl } from "./constants";

export function DownloadButton() {
  return (
    <Button
      asChild
      variant="outline"
      size="sm"
      className="border-white/20 bg-white/5 text-white hover:bg-white/10 hover:text-white"
    >
      <a aria-label="Download Unbound for Apple Silicon macOS" href={macOsDownloadUrl}>
        <Download className="size-4" />
        Download
      </a>
    </Button>
  );
}
