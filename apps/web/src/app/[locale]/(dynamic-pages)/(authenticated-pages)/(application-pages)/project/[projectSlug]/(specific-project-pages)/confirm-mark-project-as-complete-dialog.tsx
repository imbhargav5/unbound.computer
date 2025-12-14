import { Check } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";

type Props = {
  onConfirm: () => void;
};

export const ConfirmMarkProjectAsCompleteDialog = ({ onConfirm }: Props) => {
  const [open, setOpen] = useState(false);

  return (
    <Dialog onOpenChange={setOpen} open={open}>
      <DialogTrigger asChild>
        <Button className="gap-2" size="default" variant="default">
          <Check className="h-5 w-5" />
          <span className="hidden sm:inline">Mark as Complete</span>
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <div className="w-fit rounded-lg bg-gray-200/50 p-3 dark:bg-gray-700/40">
            <Check className="h-6 w-6" />
          </div>
          <div className="p-1">
            <DialogTitle className="text-lg">
              Mark Project as Complete
            </DialogTitle>
            <DialogDescription className="text-base">
              Are you sure you want to mark this project as complete?
            </DialogDescription>
          </div>
        </DialogHeader>
        <DialogFooter className="mt-8">
          <Button
            onClick={() => {
              setOpen(false);
            }}
            type="button"
            variant="outline"
          >
            Cancel
          </Button>
          <Button
            onClick={() => {
              onConfirm();
              setOpen(false);
            }}
            type="button"
            variant="default"
          >
            Confirm
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
