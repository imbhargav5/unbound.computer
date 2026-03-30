"use client";

import { useCallback, useEffect, useState } from "react";

export type CardSize = "small" | "medium" | "large";
export type StatusFilter = "all" | "active" | "paused" | "ended";

export type ColumnConfig = {
  id: string;
  repositoryId: string;
  repositoryName: string;
  statusFilter: StatusFilter;
  cardSize: CardSize;
};

export type DeckConfig = {
  id: string;
  name: string;
  columns: ColumnConfig[];
  createdAt: string;
};

const STORAGE_KEY = "unbound-deck-configs";

function loadDecks(): DeckConfig[] {
  if (typeof window === "undefined") {
    return [];
  }
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) {
      return [];
    }
    return JSON.parse(raw) as DeckConfig[];
  } catch {
    return [];
  }
}

function saveDecks(decks: DeckConfig[]) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(decks));
}

export function useDeckConfig() {
  const [decks, setDecks] = useState<DeckConfig[]>([]);
  const [isLoaded, setIsLoaded] = useState(false);

  useEffect(() => {
    setDecks(loadDecks());
    setIsLoaded(true);
  }, []);

  useEffect(() => {
    const handleStorage = (e: StorageEvent) => {
      if (e.key === STORAGE_KEY) {
        setDecks(loadDecks());
      }
    };
    window.addEventListener("storage", handleStorage);
    return () => window.removeEventListener("storage", handleStorage);
  }, []);

  const persist = useCallback((updated: DeckConfig[]) => {
    setDecks(updated);
    saveDecks(updated);
  }, []);

  const createDeck = useCallback(
    (name: string): DeckConfig => {
      const deck: DeckConfig = {
        id: crypto.randomUUID(),
        name,
        columns: [],
        createdAt: new Date().toISOString(),
      };
      persist([...decks, deck]);
      return deck;
    },
    [decks, persist],
  );

  const deleteDeck = useCallback(
    (deckId: string) => {
      persist(decks.filter((d) => d.id !== deckId));
    },
    [decks, persist],
  );

  const updateDeckName = useCallback(
    (deckId: string, name: string) => {
      persist(decks.map((d) => (d.id === deckId ? { ...d, name } : d)));
    },
    [decks, persist],
  );

  const addColumn = useCallback(
    (deckId: string, column: Omit<ColumnConfig, "id">) => {
      const newColumn: ColumnConfig = {
        ...column,
        id: crypto.randomUUID(),
      };
      persist(
        decks.map((d) =>
          d.id === deckId ? { ...d, columns: [...d.columns, newColumn] } : d,
        ),
      );
    },
    [decks, persist],
  );

  const removeColumn = useCallback(
    (deckId: string, columnId: string) => {
      persist(
        decks.map((d) =>
          d.id === deckId
            ? { ...d, columns: d.columns.filter((c) => c.id !== columnId) }
            : d,
        ),
      );
    },
    [decks, persist],
  );

  return {
    decks,
    isLoaded,
    createDeck,
    deleteDeck,
    updateDeckName,
    addColumn,
    removeColumn,
  };
}
