
'use client';

import { type ReactNode } from 'react';
import FormBackground from './form-background.svg';
import './graphic-background.css';
import { StackedCards } from './StackedCards';




export function ClientLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex h-screen border-2 border-black">
      <div className="w-1/2 p-8 flex items-center relative justify-center h-full">
        <div className="absolute inset-0 -z-10 h-full">
          <FormBackground className="w-full h-full object-cover" viewBox="0 0 1200 800" preserveAspectRatio="xMidYMid slice" />
        </div>
        <div className="max-w-xl">{children}</div>
      </div>
      <div className="w-1/2 border-l-2 border-black relative flex items-center relative justify-center h-full">
        <div className="absolute inset-0 -z-10 h-full graphic-background">
        </div>
        <div className="w-full px-16">
          <StackedCards
            images={[
              '/assets/marketing/landing-1.jpg',
              '/assets/marketing/dashboard-2.jpg',
              '/assets/marketing/docs-3.jpg',
            ]}
          />
        </div>
        {/* <Card className="max-w-xl ">
          <CardHeader>
            <CardTitle className="text-3xl font-bold text-center">Join Our Community</CardTitle>
          </CardHeader>
          <CardContent className="text-center">
            <p className="mb-4">
              "This platform has revolutionized the way we manage our projects. It's intuitive, powerful, and a joy to use!"
            </p>
            <p className="font-semibold">- Jane Doe, CEO of TechCorp</p>
          </CardContent>
        </Card> */}
      </div>
    </div>
  );
}
