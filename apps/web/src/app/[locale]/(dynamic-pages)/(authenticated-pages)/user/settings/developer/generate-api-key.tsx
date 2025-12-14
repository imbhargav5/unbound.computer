"use client";

import { useAction } from "next-cool-action/hooks";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { generateUnkeyTokenAction } from "@/data/user/unkey";
import { useRouter } from "@/i18n/navigation";
import { ViewApiKeyDialog } from "./view-api-key-dialog";

type GenerateUnkeyTokenActionResult = Awaited<
  ReturnType<typeof generateUnkeyTokenAction>
>;

export function GenerateApiKey() {
  const router = useRouter();
  const [step, setStep] = useState<"form" | "copy_modal" | "complete">("form");
  const [keyPreview, setKeyPreview] = useState<string | null>(null);
  const toastRef = useRef<string | number | undefined>(undefined);

  const { execute, isPending } = useAction(generateUnkeyTokenAction, {
    onExecute: () => {
      toastRef.current = toast.loading("Generating new API Key...");
    },
    onSuccess: ({ data }) => {
      toast.success("API Key generated successfully", { id: toastRef.current });
      toastRef.current = undefined;
      if (data) {
        setStep("copy_modal");
        setKeyPreview(data.key);
      }
    },
    onError: ({ error }) => {
      const errorMessage = error.serverError ?? "Failed to generate API Key";
      toast.error(errorMessage, { id: toastRef.current });
      toastRef.current = undefined;
    },
  });

  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    execute();
  };

  return (
    <>
      <form className="max-w-sm" onSubmit={handleSubmit}>
        <div className="space-y-2">
          <Button
            className="block w-full"
            disabled={isPending}
            size="lg"
            type="submit"
          >
            {isPending ? "Generating new API Key..." : "Generate API Key"}
          </Button>
        </div>
      </form>

      {step === "copy_modal" && keyPreview && (
        <ViewApiKeyDialog
          apiKey={keyPreview}
          onCompleted={() => {
            setStep("complete");
          }}
        />
      )}
    </>
  );
}
