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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type {
  CardSize,
  ColumnConfig,
  StatusFilter,
} from "@/hooks/use-deck-config";
import type { getUserRepositories } from "@/data/user/repositories";

type Repository = Awaited<ReturnType<typeof getUserRepositories>>[number];

type AddColumnDialogProps = {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onAddColumn: (column: Omit<ColumnConfig, "id">) => void;
  repositories: Repository[];
};

export function AddColumnDialog({
  open,
  onOpenChange,
  onAddColumn,
  repositories,
}: AddColumnDialogProps) {
  const [repositoryId, setRepositoryId] = useState("");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [cardSize, setCardSize] = useState<CardSize>("small");

  const selectedRepo = repositories.find((r) => r.id === repositoryId);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!repositoryId || !selectedRepo) {
      return;
    }
    onAddColumn({
      repositoryId,
      repositoryName: selectedRepo.name,
      statusFilter,
      cardSize,
    });
    setRepositoryId("");
    setStatusFilter("all");
    setCardSize("small");
    onOpenChange(false);
  };

  return (
    <Dialog onOpenChange={onOpenChange} open={open}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Add Column</DialogTitle>
            <DialogDescription>
              Choose a repository and configure how sessions are displayed.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-2">
              <label className="font-medium text-sm" htmlFor="repo-select">
                Repository
              </label>
              <Select onValueChange={setRepositoryId} value={repositoryId}>
                <SelectTrigger className="w-full" id="repo-select">
                  <SelectValue placeholder="Select repository" />
                </SelectTrigger>
                <SelectContent>
                  {repositories.map((repo) => (
                    <SelectItem key={repo.id} value={repo.id}>
                      {repo.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <label className="font-medium text-sm" htmlFor="status-select">
                Status Filter
              </label>
              <Select
                onValueChange={(v) => setStatusFilter(v as StatusFilter)}
                value={statusFilter}
              >
                <SelectTrigger className="w-full" id="status-select">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All</SelectItem>
                  <SelectItem value="active">Active</SelectItem>
                  <SelectItem value="paused">Paused</SelectItem>
                  <SelectItem value="ended">Ended</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-2">
              <label className="font-medium text-sm" htmlFor="size-select">
                Card Size
              </label>
              <Select
                onValueChange={(v) => setCardSize(v as CardSize)}
                value={cardSize}
              >
                <SelectTrigger className="w-full" id="size-select">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="small">Small</SelectItem>
                  <SelectItem value="medium">Medium</SelectItem>
                  <SelectItem value="large">Large</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter>
            <Button
              onClick={() => onOpenChange(false)}
              type="button"
              variant="outline"
            >
              Cancel
            </Button>
            <Button disabled={!repositoryId} type="submit">
              Add Column
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
