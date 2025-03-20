"use client";
import { Settings } from "lucide-react";

import { Card, CardDescription, CardHeader, CardTitle } from "../ui/card";

interface RedirectingPleaseWaitCardProps {
  message: string;
  heading: string;
}

export function RedirectingPleaseWaitCard({
  message,
  heading,
}: RedirectingPleaseWaitCardProps) {
  return (
    <div className="w-full max-w-md mx-auto px-4">
      <Card className="border shadow-md overflow-hidden p-1 min-w-[320px] w-full">
        <CardHeader className="space-y-4 pt-8 pb-6">
          <div className="rounded-full bg-muted/30 p-3 w-fit mx-auto">
            <Settings className="w-8 h-8" />
          </div>
          <div className="space-y-1.5">
            <CardTitle className="text-center text-xl font-semibold">
              {heading}
            </CardTitle>
            <CardDescription className="text-center max-w-xs mx-auto">
              {message}
            </CardDescription>
          </div>
        </CardHeader>
      </Card>
    </div>
  );
}
