import { Download } from "lucide-react";
import { Button } from "@/components/ui/button";
import { macOsDownloadUrl } from "./constants";

export function DownloadButton() {
  return (
    <Button
      asChild
      className="border-white/20 bg-white/5 text-white hover:bg-white/10 hover:text-white"
      size="sm"
      variant="outline"
    >
      <a
        aria-label="Download Unbound for Apple Silicon macOS"
        href={macOsDownloadUrl}
      >
        <Download className="size-4" />
        Download
      </a>
    </Button>
  );
}
