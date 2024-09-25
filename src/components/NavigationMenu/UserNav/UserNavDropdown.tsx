// UserNavDropdown.tsx
'use client';

import { GiveFeedbackDialog } from '@/app/[locale]/(dynamic-pages)/(public-pages)/feedback/[feedbackId]/GiveFeedbackDialog';
import { Link } from '@/components/intl-link';
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { motion } from "framer-motion";
import { Computer, Lock, LogOut, Mail, Server, User } from 'lucide-react';
import { FeatureViewModal } from './FeatureViewModal';

const MotionDiv = motion.div;

const menuItemAnimation = {
  hidden: { opacity: 0, y: 5 },
  show: {
    opacity: 1,
    y: 0,
    transition: {
      type: "spring",
      stiffness: 400,
      damping: 30,
    }
  }
};

const containerAnimation = {
  hidden: { opacity: 0 },
  show: {
    opacity: 1,
    transition: {
      staggerChildren: 0.05,
      delayChildren: 0.1,
    }
  }
};

export const UserNavDropdown = ({
  avatarUrl,
  userFullname,
  userEmail,
  userId,
  isUserAppAdmin,
}: {
  avatarUrl: string;
  userFullname: string;
  userEmail: string;
  userId: string;
  isUserAppAdmin: boolean;
}) => {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button data-testid="user-nav-avatar" variant="ghost" className="relative h-8 w-8 rounded-full">
          <Avatar className="h-8 w-8">
            <AvatarImage src={avatarUrl} alt={userFullname} />
            <AvatarFallback>{userFullname.charAt(0)}</AvatarFallback>
          </Avatar>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent className="w-56" align="end" forceMount>
        <MotionDiv
          variants={containerAnimation}
          initial="hidden"
          animate="show"
        >
          <DropdownMenuLabel className="font-normal">
            <div className="flex flex-col space-y-1">
              <p className="text-sm font-medium leading-none">{userFullname}</p>
              <p className="text-xs leading-none text-muted-foreground">{userEmail}</p>
            </div>
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
          <DropdownMenuGroup>
            <MotionDiv variants={menuItemAnimation}>
              <DropdownMenuItem>
                <Link href="/user/settings" className="flex items-center w-full">
                  <User className="mr-2 h-4 w-4" /> Account settings
                </Link>
              </DropdownMenuItem>
            </MotionDiv>
            <MotionDiv variants={menuItemAnimation}>
              <DropdownMenuItem>
                <Link href="/user/settings/developer" className="flex items-center w-full">
                  <Computer className="mr-2 h-4 w-4" /> Developer Settings
                </Link>
              </DropdownMenuItem>
            </MotionDiv>
            <MotionDiv variants={menuItemAnimation}>
              <DropdownMenuItem>
                <Link href="/user/settings/security" className="flex items-center w-full">
                  <Lock className="mr-2 h-4 w-4" /> Security Settings
                </Link>
              </DropdownMenuItem>
            </MotionDiv>
            {isUserAppAdmin && (
              <MotionDiv variants={menuItemAnimation}>
                <DropdownMenuItem>
                  <Link href="/app_admin" className="flex items-center w-full">
                    <Server className="mr-2 h-4 w-4" /> Admin Panel
                  </Link>
                </DropdownMenuItem>
              </MotionDiv>
            )}
          </DropdownMenuGroup>
          <DropdownMenuSeparator />
          <MotionDiv variants={menuItemAnimation}>
            <DropdownMenuItem asChild>
              <FeatureViewModal />
            </DropdownMenuItem>
          </MotionDiv>
          <MotionDiv variants={menuItemAnimation}>
            <DropdownMenuItem asChild>
              <GiveFeedbackDialog>
                <div data-testid="feedback-link" className="flex items-center w-full">
                  <Mail className="mr-2 h-4 w-4" /> Feedback
                </div>
              </GiveFeedbackDialog>
            </DropdownMenuItem>
          </MotionDiv>
          <DropdownMenuSeparator />
          <MotionDiv variants={menuItemAnimation}>
            <DropdownMenuItem>
              <Link href="/logout" prefetch={false} className="flex items-center w-full text-red-500 hover:text-red-600">
                <LogOut className="mr-2 h-4 w-4" /> Log out
              </Link>
            </DropdownMenuItem>
          </MotionDiv>
        </MotionDiv>
      </DropdownMenuContent>
    </DropdownMenu>
  );
};
