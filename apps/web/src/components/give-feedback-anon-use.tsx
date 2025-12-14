"use client";
import { useState } from "react";
import { Link } from "@/components/intl-link";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { cn } from "@/utils/cn";

type Props = {
  children: React.ReactNode;
  className?: string;
};

export const GiveFeedbackAnonUser = ({ children, className }: Props) => {
  const [isOpen, setIsOpen] = useState(false);

  return (
    <Dialog
      onOpenChange={(newIsOpen) => {
        setIsOpen(newIsOpen);
      }}
      open={isOpen}
    >
      <DialogTrigger className={cn("w-full", className)}>
        {children}
      </DialogTrigger>

      <DialogContent>
        <DialogHeader>
          <div>
            <DialogTitle className="flex items-start gap-2 text-lg">
              Please login to continue
            </DialogTitle>
            <DialogDescription className="text-base">
              You will be able to give us feedback after you login
            </DialogDescription>
          </div>
        </DialogHeader>
        <div className="flex justify-end gap-2">
          <Button onClick={() => setIsOpen(false)} variant="outline">
            Cancel
          </Button>

          <Link className="w-full lg:w-fit" href="/login">
            <Button variant="default">Log In</Button>
          </Link>
        </div>
      </DialogContent>
    </Dialog>
  );
};
