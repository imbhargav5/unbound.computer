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
  onSubmit: () => void;
};

export const SubmitProjectForApprovalDialog = ({ onSubmit }: Props) => {
  const [open, setOpen] = useState(false);

  return (
    <Dialog onOpenChange={setOpen} open={open}>
      <DialogTrigger asChild>
        <Button size="default" variant="default">
          <Check className="mr-2 h-5 w-5" /> Submit for Approval
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <div className="w-fit rounded-lg bg-gray-200/50 p-3 dark:bg-gray-700/40">
            <Check className="h-6 w-6" />
          </div>
          <div className="p-1">
            <DialogTitle className="text-lg">
              Submit Project for Approval
            </DialogTitle>
            <DialogDescription className="text-base">
              Are you sure you want to submit this project for approval?
            </DialogDescription>
          </div>
        </DialogHeader>
        <DialogFooter>
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
              onSubmit();
              setOpen(false);
            }}
            type="button"
          >
            Submit
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};
