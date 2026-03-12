"use client";

import { Download } from "lucide-react";
import { Button } from "@/components/ui/button";

export function DownloadButton() {
  return (
    <Button
      variant="outline"
      size="sm"
      className="border-white/20 bg-white/5 text-white hover:bg-white/10 hover:text-white"
      onClick={() => {
        alert("Coming soon!");
      }}
    >
      <Download className="size-4" />
      Download
    </Button>
  );
}
