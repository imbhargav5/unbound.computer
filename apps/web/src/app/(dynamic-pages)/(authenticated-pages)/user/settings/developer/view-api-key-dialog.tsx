"use client";
import { Copy, CopyCheck } from "lucide-react";
import { useState } from "react";
import { CopyToClipboard } from "react-copy-to-clipboard";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";

type Props = {
  apiKey: string;
  onCompleted: () => void;
};

export const ViewApiKeyDialog = ({ apiKey, onCompleted }: Props) => {
  const [open, setOpen] = useState(true);
  const [isCopied, setIsCopied] = useState(false);

  return (
    <Dialog open={open}>
      <DialogContent className="hide-dialog-close sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>API Key</DialogTitle>
          <DialogDescription>
            This key will never be displayed again. Please store it in a safe
            place.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <CopyToClipboard onCopy={() => setIsCopied(true)} text={apiKey}>
            <div className="flex items-center space-x-2">
              <input
                className="grow cursor-pointer rounded border p-2"
                readOnly
                type="text"
                value={apiKey}
              />
              {isCopied ? <CopyCheck /> : <Copy />}
            </div>
          </CopyToClipboard>
          {isCopied ? <span>Copied to clipboard!</span> : null}
        </div>
        <DialogFooter>
          <Button
            onClick={() => {
              setOpen(false);
              onCompleted();
            }}
            type="button"
          >
            I have stored my API key
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
