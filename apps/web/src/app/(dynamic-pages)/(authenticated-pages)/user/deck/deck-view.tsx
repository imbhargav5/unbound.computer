"use client";

import { Home, Plus } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { useDeckConfig } from "@/hooks/use-deck-config";
import type { DeckSession } from "@/data/user/deck-sessions";
import type { getUserRepositories } from "@/data/user/repositories";
import { AddColumnDialog } from "./add-column-dialog";
import { CreateDeckDialog } from "./create-deck-dialog";
import { CustomDeck } from "./custom-deck";
import { HomeDeck } from "./home-deck";

type Repository = Awaited<ReturnType<typeof getUserRepositories>>[number];

type DeckViewProps = {
  repositories: Repository[];
  sessions: DeckSession[];
};

export function DeckView({ repositories, sessions }: DeckViewProps) {
  const {
    decks,
    isLoaded,
    createDeck,
    deleteDeck,
    updateDeckName,
    addColumn,
    removeColumn,
  } = useDeckConfig();

  const [activeTab, setActiveTab] = useState("home");
  const [createDeckOpen, setCreateDeckOpen] = useState(false);
  const [addColumnDeckId, setAddColumnDeckId] = useState<string | null>(null);

  const handleCreateDeck = (name: string) => {
    const deck = createDeck(name);
    setActiveTab(deck.id);
  };

  const handleDeleteDeck = (deckId: string) => {
    deleteDeck(deckId);
    setActiveTab("home");
  };

  return (
    <div className="-mx-6 -my-6">
      <Tabs onValueChange={setActiveTab} value={activeTab}>
        <div className="flex items-center border-b px-4 py-2">
          <TabsList>
            <TabsTrigger value="home">
              <Home className="mr-1 h-4 w-4" />
              Home
            </TabsTrigger>
            {isLoaded &&
              decks.map((deck) => (
                <TabsTrigger key={deck.id} value={deck.id}>
                  {deck.name}
                </TabsTrigger>
              ))}
          </TabsList>
          <Button
            className="ml-2"
            onClick={() => setCreateDeckOpen(true)}
            size="sm"
            variant="ghost"
          >
            <Plus className="mr-1 h-4 w-4" />
            New Deck
          </Button>
        </div>

        <div className="px-4 py-4">
          <TabsContent value="home">
            <HomeDeck repositories={repositories} sessions={sessions} />
          </TabsContent>

          {isLoaded &&
            decks.map((deck) => (
              <TabsContent key={deck.id} value={deck.id}>
                <CustomDeck
                  deck={deck}
                  onAddColumn={() => setAddColumnDeckId(deck.id)}
                  onDeleteDeck={() => handleDeleteDeck(deck.id)}
                  onRemoveColumn={(columnId) => removeColumn(deck.id, columnId)}
                  onRenameDeck={(name) => updateDeckName(deck.id, name)}
                  repositories={repositories}
                  sessions={sessions}
                />
              </TabsContent>
            ))}
        </div>
      </Tabs>

      <CreateDeckDialog
        onCreateDeck={handleCreateDeck}
        onOpenChange={setCreateDeckOpen}
        open={createDeckOpen}
      />

      {addColumnDeckId && (
        <AddColumnDialog
          onAddColumn={(column) => addColumn(addColumnDeckId, column)}
          onOpenChange={(open) => {
            if (!open) {
              setAddColumnDeckId(null);
            }
          }}
          open={Boolean(addColumnDeckId)}
          repositories={repositories}
        />
      )}
    </div>
  );
}
