'use client'
import { AspectRatio } from "@/components/ui/aspect-ratio";
import { Card } from "@/components/ui/card";
import { motion } from 'framer-motion';
import Image from "next/image";
import React, { useEffect, useState } from 'react';

const CARD_COLORS = ["#266678", "#cb7c7a", "#36a18b", "#cda35f", "#747474"];
const CARD_OFFSET = 10;
const SCALE_FACTOR = 0.06;

interface CardStackProps {
  images: string[];
  interval?: number;
}

function withRandomKey(imageUrl: string, index: number) {
  const random = Math.random();
  return `${imageUrl}?r=${random}`;
}

export const StackedCards: React.FC<CardStackProps> = ({ images, interval = 3000 }) => {
  const [cards, setCards] = useState<string[]>(() => images.map(withRandomKey));

  const moveToEnd = () => {
    setCards(prevCards => {
      const [firstCard, ...rest] = prevCards;
      return [...rest, firstCard];
    });
  };

  useEffect(() => {
    const timer = setInterval(() => {
      moveToEnd();
    }, interval);

    return () => clearInterval(timer);
  }, [interval]);

  return (
    <div className="relative flex items-center justify-center ">
      <AspectRatio className="relative w-full" ratio={16 / 10}>
        <ul className="relative w-full h-full">
          {cards.map((imageUrl, index) => {
            const canDrag = index === 0;
            const color = CARD_COLORS[index % CARD_COLORS.length];

            return (
              <motion.li
                key={imageUrl + index}
                className="absolute inset-0 rounded-lg list-none origin-top-center"
                style={{ backgroundColor: color, cursor: canDrag ? 'grab' : 'auto' }}
                animate={{
                  top: index * -CARD_OFFSET,
                  scale: 1 - index * SCALE_FACTOR,
                  zIndex: cards.length - index
                }}
                drag={canDrag ? 'y' : false}
                dragConstraints={{
                  top: 0,
                  bottom: 0
                }}
                onDragEnd={() => moveToEnd()}
              >
                <Card className="w-full h-full bg-transparent p-4">
                  <Image
                    src={imageUrl}
                    alt={`Card ${index + 1}`}
                    fill
                    className="rounded-md object-cover"
                    loader={({ src }) => src}
                  />
                </Card>
              </motion.li>
            );
          })}
        </ul>
      </AspectRatio>

    </div>
  );
};
