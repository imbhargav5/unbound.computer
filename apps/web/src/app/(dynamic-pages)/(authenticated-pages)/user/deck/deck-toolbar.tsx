"use client";

import { Plus, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";

type DeckToolbarProps = {
  deckName: string;
  onAddColumn: () => void;
  onDeleteDeck: () => void;
  onRenameDeck: (name: string) => void;
};

export function DeckToolbar({
  deckName,
  onAddColumn,
  onDeleteDeck,
}: DeckToolbarProps) {
  return (
    <div className="flex items-center justify-between">
      <h2 className="font-semibold text-lg">{deckName}</h2>
      <div className="flex items-center gap-2">
        <Button onClick={onAddColumn} size="sm" variant="outline">
          <Plus className="mr-1 h-4 w-4" />
          Add Column
        </Button>
        <Button onClick={onDeleteDeck} size="sm" variant="ghost">
          <Trash2 className="mr-1 h-4 w-4" />
          Delete Deck
        </Button>
      </div>
    </div>
  );
}
