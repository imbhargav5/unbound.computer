"use client";
import { AspectRatio } from "@/components/ui/aspect-ratio";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogTrigger,
} from "@/components/ui/dialog";
import { AnimatePresence, motion } from "framer-motion";
import { HelpCircle } from "lucide-react";
import Image from "next/image";
import { useState } from "react";

const featureList = [
  {
    title: "Organisations, Teams and Invitations",
    description: (
      <p>
        Organisations, team members and team invitations is built-in. This means
        that your next SAAS project will allow your customers to manage
        organisations right off the bat. NextBase comes with Supabase configured
        with all the necessary tables to manage members of an organization.
        Every organization also has it&apos;s own Stripe plan.
      </p>
    ),
    image: "/assets/login-asset-dashboard.png",
  },
  {
    title: "User Authentication built in",
    description: (
      <p>
        Start building your app with NextBase and you&apos;ll get a
        full-featured authentication system, out of the box. More than 15
        authentication providers such as Google, GitHub, Twitter, Facebook,
        Apple, Discord etc are supported.
      </p>
    ),
    image: "/assets/onboardingFeatures/authentication.png",
  },
  {
    title: "Admin Panel",
    description: (
      <p>
        Admin Panel is built in. This means that you can manage a secret area
        within your app where you can manage users and organizations, etc.
      </p>
    ),
    image: "/assets/onboardingFeatures/adminPanel.png",
  },
  {
    title: "Next.js 13, Supabase and Typescript",
    description: (
      <p>
        You get all of the latest features and performance improvements that
        come with Next.js 13. These include the new Image component, built-in
        TypeScript support, the new app folder, layouts, server components and
        more! Your frontend will automatically update types and keep the project
        in sync when you update Supabase tables.
      </p>
    ),
    image: "/assets/onboardingFeatures/nextjs-type-supa.png",
  },
  {
    title: "Incredible performance with layouts, server components",
    description: (
      <p>
        Nextbase offers world-class features such as app folder, layouts, server
        components, and server-side rendering to optimize data fetching and
        provide the best user experience. Layouts such as authenticated layout,
        external page layout, login layout, application admin layout
        authenticated, external, login, and admin are pre-configured.
      </p>
    ),
    image: "/assets/onboardingFeatures/layout.png",
  },
];

// ... (featureList remains the same)

export function FeatureViewModal() {
  const [open, setOpen] = useState(false);
  const [currentFeatureIndex, setCurrentFeatureIndex] = useState(0);

  const handleNext = () => {
    setCurrentFeatureIndex((prevIndex) => (prevIndex + 1) % featureList.length);
  };

  const handlePrevious = () => {
    setCurrentFeatureIndex(
      (prevIndex) => (prevIndex - 1 + featureList.length) % featureList.length,
    );
  };

  const handleClose = () => {
    setOpen(false);
    setCurrentFeatureIndex(0);
  };

  const currentFeature = featureList[currentFeatureIndex];

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="ghost" className="w-full justify-start px-2 py-1.5">
          <HelpCircle className="mr-2 h-4 w-4" />
          Help
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[425px]">
        <AnimatePresence mode="wait">
          <motion.div
            key={currentFeatureIndex}
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -20 }}
            transition={{ duration: 0.2 }}
          >
            <div className="space-y-4">
              <p className="text-sm text-muted-foreground">
                {currentFeatureIndex + 1} / {featureList.length}
              </p>
              <AspectRatio ratio={16 / 9} className="bg-muted">
                <Image
                  src={currentFeature.image}
                  alt="Feature preview"
                  fill
                  className="rounded-md object-cover"
                />
              </AspectRatio>
              <h3 className="text-lg font-semibold">{currentFeature.title}</h3>
              <div className="text-sm text-muted-foreground">
                {currentFeature.description}
              </div>
            </div>
          </motion.div>
        </AnimatePresence>
        <DialogFooter className="mt-6">
          <Button
            variant="outline"
            onClick={handlePrevious}
            disabled={currentFeatureIndex === 0}
          >
            Previous
          </Button>
          {currentFeatureIndex < featureList.length - 1 ? (
            <Button onClick={handleNext}>Next</Button>
          ) : (
            <Button onClick={handleClose}>Close</Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
