"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";

type CreateDeckDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCreateDeck: (name: string) => void;
};

export function CreateDeckDialog({
  open,
  onOpenChange,
  onCreateDeck,
}: CreateDeckDialogProps) {
  const [name, setName] = useState("");

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) {
      return;
    }
    onCreateDeck(trimmed);
    setName("");
    onOpenChange(false);
  };

  return (
    <Dialog onOpenChange={onOpenChange} open={open}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Create New Deck</DialogTitle>
            <DialogDescription>
              Create a custom deck to organize your sessions your way.
            </DialogDescription>
          </DialogHeader>
          <div className="py-4">
            <Input
              onChange={(e) => setName(e.target.value)}
              placeholder="Deck name"
              value={name}
            />
          </div>
          <DialogFooter>
            <Button
              onClick={() => onOpenChange(false)}
              type="button"
              variant="outline"
            >
              Cancel
            </Button>
            <Button disabled={!name.trim()} type="submit">
              Create
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
