"use client";

import { motion } from "motion/react";
import Image from "next/image";
import { type ReactNode, useState } from "react";
import { Link } from "@/components/intl-link";
import { AspectRatio } from "@/components/ui/aspect-ratio";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { SidebarMenuButton } from "@/components/ui/sidebar";
import { Typography } from "@/components/ui/typography-ui";
import type { SlimWorkspace } from "@/types";
import { getWorkspaceSubPath } from "@/utils/workspaces";
export function ProFeatureGateDialog({
  workspace,
  label,
  icon,
}: {
  workspace: SlimWorkspace;
  label: string;
  icon: ReactNode;
}) {
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  return (
    <Dialog onOpenChange={setIsDialogOpen} open={isDialogOpen}>
      <DialogTrigger asChild className="mb-0 w-full">
        <SidebarMenuButton>
          {icon}
          <span>{label}</span>
          <span className="rounded-md bg-tremor-brand-subtle px-2 py-1 font-medium text-primary-foreground text-xs uppercase">
            Pro
          </span>
        </SidebarMenuButton>
      </DialogTrigger>
      <DialogContent className="hide-dialog-close flex flex-col items-center gap-2">
        <AspectRatio
          className="relative h-full overflow-hidden rounded-lg"
          ratio={16 / 9}
        >
          <motion.div
            animate={{ scale: 1, filter: "blur(0px)" }}
            className="absolute inset-0 z-20 flex h-full w-full place-content-center"
            initial={{ scale: 5, filter: "blur(5px)" }}
            transition={{ duration: 0.8, ease: [0.22, 0.61, 0.36, 1] }}
          >
            <Image
              alt="Feature Pro"
              className="z-10"
              fill
              src="/assets/feature-pro-text.png"
            />
          </motion.div>
          <motion.div
            animate={{ scale: 1, filter: "blur(0px)" }}
            className="absolute inset-0 flex h-full w-full place-content-center"
            initial={{ scale: 2, filter: "blur(2px)" }}
            transition={{ duration: 0.8, ease: [0.22, 0.61, 0.36, 1] }}
          >
            <Image
              alt="Feature Pro"
              className="z-10"
              fill
              src="/assets/feature-pro.jpeg"
            />
          </motion.div>
        </AspectRatio>
        <div className="mt-4 flex items-center justify-start gap-2.5">
          <DialogTitle className="mt-0">Upgrade to</DialogTitle>
          <span className="flex place-content-center rounded-md bg-primary px-2 py-1 text-primary-foreground text-sm">
            PRO
          </span>
        </div>
        <Typography.P className="mb-4 text-center text-muted-foreground">
          This is a dummy feature gate dialog. You can show this dialog to
          describe the advanced features, unlimited team members, collaborative
          workspace and more and protect access to the feature until the user
          upgrades to PRO.
        </Typography.P>
        <Link
          className="w-full"
          href={getWorkspaceSubPath(workspace, "/settings/billing")}
          onClick={() => setIsDialogOpen(false)}
        >
          <Button className="w-full">Upgrade to Pro</Button>
        </Link>
      </DialogContent>
    </Dialog>
  );
}
