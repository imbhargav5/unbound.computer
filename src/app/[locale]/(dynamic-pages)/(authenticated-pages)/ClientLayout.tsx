'use client';

import PostHogProvider from '@/contexts/PostHogProvider';
import dynamic from 'next/dynamic';

import { useState } from 'react';
import { useWindowSize } from 'rooks';


const Confetti = dynamic(
  () => import('react-confetti').then((mod) => mod.default),
  { ssr: false },
);

export function ClientLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { innerHeight: _innerHeight, innerWidth: _innerWidth } =
    useWindowSize();
  const innerHeight = _innerHeight ?? 0;
  const innerWidth = _innerWidth ?? 0;

  const [showConfetti, setShowConfetti] = useState<boolean>(false);



  return (
    <PostHogProvider>
      <div className="flex overflow-y-auto flex-col h-full w-full">
        <div className="flex h-full">
          <div className="flex-1 h-auto overflow-auto">
            <div className="space-y-10">{children}</div>
          </div>
          {showConfetti ? (
            <Confetti
              confettiSource={{
                x: innerWidth / 2,
                y: innerHeight / 3,
                w: 0,
                h: 0,
              }}
              numberOfPieces={150}
              gravity={0.1}
              initialVelocityY={20}
              initialVelocityX={20}
              recycle={false}
              tweenDuration={1000}
              run={true}
              width={innerWidth}
              height={innerHeight}
            />
          ) : null}{' '}
        </div>
      </div>
    </PostHogProvider>
  );
}
