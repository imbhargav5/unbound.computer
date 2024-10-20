import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar";
import { Typography } from "@/components/ui/Typography";
import { SlimWorkspace } from "@/types";
import {
  BookOpen,
  DollarSign,
  FileText,
  GitBranch,
  Image,
  Mail,
  MessageSquare,
  Users,
} from "lucide-react";
import { type ReactNode } from "react";

interface TipDialogProps {
  workspace: SlimWorkspace;
  label: string;
  icon: ReactNode;
  content: ReactNode;
  index: number;
}

function TipDialog({ workspace, label, icon, content, index }: TipDialogProps) {
  return (
    <Dialog>
      <DialogTrigger asChild>
        <SidebarMenuItem>
          <SidebarMenuButton>
            {icon}
            <span>
              {index + 1}. {label}
            </span>
          </SidebarMenuButton>
        </SidebarMenuItem>
      </DialogTrigger>
      <DialogContent className="flex flex-col gap-2">
        <DialogHeader>
          <div className="p-1">
            <DialogTitle className="text-lg">{label}</DialogTitle>
          </div>
        </DialogHeader>
        {content}
      </DialogContent>
    </Dialog>
  );
}

export function SidebarTipsNav({ workspace }: { workspace: SlimWorkspace }) {
  const tips = [
    {
      label: "Create a Team Workspace",
      icon: <Users className="h-4 w-4" />,
      content: (
        <div>
          <Typography.P>
            Learn how to create and manage a team workspace for collaborative
            projects.
          </Typography.P>
        </div>
      ),
    },
    {
      label: "Invite users to team",
      icon: <Mail className="h-4 w-4" />,
      content: (
        <Typography.P>
          Invite users to your team worksapce, assign privileges and collaborate
          together.
        </Typography.P>
      ),
    },
    {
      label: "Make an Application Admin User",
      icon: <GitBranch className="h-4 w-4" />,
      content: (
        <Typography.P>
          Discover the process of assigning admin privileges to users in your
          application.
        </Typography.P>
      ),
    },
    {
      label: "Connect Stripe",
      icon: <DollarSign className="h-4 w-4" />,
      content: (
        <Typography.P>
          Set up Stripe integration for seamless payment processing in your
          application.
        </Typography.P>
      ),
    },
    {
      label: "Write an Admin Blog Post",
      icon: <FileText className="h-4 w-4" />,
      content: (
        <Typography.P>
          Learn how to create and publish blog posts using the admin interface.
        </Typography.P>
      ),
    },
    {
      label: "Write a Docs Article",
      icon: <BookOpen className="h-4 w-4" />,
      content: (
        <Typography.P>
          Explore the process of writing and organizing documentation for your
          project.
        </Typography.P>
      ),
    },
    {
      label: "Chat using OpenAI",
      icon: <MessageSquare className="h-4 w-4" />,
      content: (
        <Typography.P>
          Integrate OpenAI&apos;s chat capabilities into your application for
          enhanced user interactions.
        </Typography.P>
      ),
    },
    {
      label: "Generate Images using OpenAI",
      icon: <Image className="h-4 w-4" />,
      content: (
        <Typography.P>
          Leverage OpenAI&apos;s image generation capabilities to create unique
          visuals for your project.
        </Typography.P>
      ),
    },
  ];

  return (
    <SidebarGroup className="group-data-[collapsible=icon]:hidden">
      <SidebarGroupLabel>Nextbase Tips</SidebarGroupLabel>
      <SidebarMenu>
        {tips.map((tip, index) => (
          <TipDialog
            key={index}
            workspace={workspace}
            label={tip.label}
            index={index}
            icon={tip.icon}
            content={tip.content}
          />
        ))}
      </SidebarMenu>
    </SidebarGroup>
  );
}
