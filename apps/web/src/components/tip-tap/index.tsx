"use client";

import { Color } from "@tiptap/extension-color";
import Image from "@tiptap/extension-image";
import { ListItem } from "@tiptap/extension-list-item";
import { TextStyle } from "@tiptap/extension-text-style";
import {
  EditorProvider,
  type JSONContent,
  useCurrentEditor,
} from "@tiptap/react";
import { StarterKit } from "@tiptap/starter-kit";
import type React from "react";
import { useRef } from "react";
import { cn } from "@/lib/utils";
import { Video } from "./extensions/video";

interface MenuBarProps {
  onImageUpload?: (file: File) => Promise<string>;
  onVideoUpload?: (file: File) => Promise<string>;
}

const MenuBar = ({ onImageUpload, onVideoUpload }: MenuBarProps) => {
  const { editor } = useCurrentEditor();
  const imageInputRef = useRef<HTMLInputElement>(null);
  const videoInputRef = useRef<HTMLInputElement>(null);

  if (!editor) {
    return null;
  }

  const handleImageUpload = async (
    event: React.ChangeEvent<HTMLInputElement>
  ) => {
    const file = event.target.files?.[0];
    if (file && onImageUpload) {
      const url = await onImageUpload(file);
      if (url) {
        editor.chain().focus().setImage({ src: url }).run();
      }
    }
    // Reset input
    if (imageInputRef.current) {
      imageInputRef.current.value = "";
    }
  };

  const handleVideoUpload = async (
    event: React.ChangeEvent<HTMLInputElement>
  ) => {
    const file = event.target.files?.[0];
    if (file && onVideoUpload) {
      const url = await onVideoUpload(file);
      if (url) {
        editor.chain().focus().setVideo({ src: url }).run();
      }
    }
    // Reset input
    if (videoInputRef.current) {
      videoInputRef.current.value = "";
    }
  };

  return (
    <div className="control-group flex flex-wrap gap-2 rounded-md bg-muted p-2">
      <div className="button-group flex flex-wrap gap-1">
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("bold")
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          disabled={!editor.can().chain().focus().toggleBold().run()}
          onClick={() => editor.chain().focus().toggleBold().run()}
          type="button"
        >
          Bold
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("italic")
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          disabled={!editor.can().chain().focus().toggleItalic().run()}
          onClick={() => editor.chain().focus().toggleItalic().run()}
          type="button"
        >
          Italic
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("strike")
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          disabled={!editor.can().chain().focus().toggleStrike().run()}
          onClick={() => editor.chain().focus().toggleStrike().run()}
          type="button"
        >
          Strike
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("code")
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          disabled={!editor.can().chain().focus().toggleCode().run()}
          onClick={() => editor.chain().focus().toggleCode().run()}
          type="button"
        >
          Code
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            "text-foreground"
          )}
          onClick={() => editor.chain().focus().unsetAllMarks().run()}
          type="button"
        >
          Clear marks
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            "text-foreground"
          )}
          onClick={() => editor.chain().focus().clearNodes().run()}
          type="button"
        >
          Clear nodes
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("paragraph")
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          onClick={() => editor.chain().focus().setParagraph().run()}
          type="button"
        >
          Paragraph
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("heading", { level: 1 })
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          onClick={() =>
            editor.chain().focus().toggleHeading({ level: 1 }).run()
          }
          type="button"
        >
          H1
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("heading", { level: 2 })
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          onClick={() =>
            editor.chain().focus().toggleHeading({ level: 2 }).run()
          }
          type="button"
        >
          H2
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("heading", { level: 3 })
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          onClick={() =>
            editor.chain().focus().toggleHeading({ level: 3 }).run()
          }
          type="button"
        >
          H3
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("heading", { level: 4 })
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          onClick={() =>
            editor.chain().focus().toggleHeading({ level: 4 }).run()
          }
          type="button"
        >
          H4
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("heading", { level: 5 })
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          onClick={() =>
            editor.chain().focus().toggleHeading({ level: 5 }).run()
          }
          type="button"
        >
          H5
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("heading", { level: 6 })
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          onClick={() =>
            editor.chain().focus().toggleHeading({ level: 6 }).run()
          }
          type="button"
        >
          H6
        </button>

        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("codeBlock")
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          onClick={() => editor.chain().focus().toggleCodeBlock().run()}
          type="button"
        >
          Code block
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("blockquote")
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          onClick={() => editor.chain().focus().toggleBlockquote().run()}
          type="button"
        >
          Blockquote
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            "text-foreground"
          )}
          onClick={() => editor.chain().focus().setHorizontalRule().run()}
          type="button"
        >
          Horizontal rule
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            "text-foreground"
          )}
          onClick={() => editor.chain().focus().setHardBreak().run()}
          type="button"
        >
          Hard break
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            "text-foreground"
          )}
          disabled={!editor.can().chain().focus().undo().run()}
          onClick={() => editor.chain().focus().undo().run()}
          type="button"
        >
          Undo
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            "text-foreground"
          )}
          disabled={!editor.can().chain().focus().redo().run()}
          onClick={() => editor.chain().focus().redo().run()}
          type="button"
        >
          Redo
        </button>
        <button
          className={cn(
            "rounded-md px-2 py-1 font-medium text-sm transition-colors",
            "border border-border bg-background hover:bg-accent",
            "disabled:cursor-not-allowed disabled:opacity-50",
            editor.isActive("textStyle", { color: "#958DF1" })
              ? "bg-accent text-accent-foreground"
              : "text-foreground"
          )}
          onClick={() => editor.chain().focus().setColor("#958DF1").run()}
          type="button"
        >
          Purple
        </button>
        {onImageUpload && (
          <>
            <button
              className={cn(
                "rounded-md px-2 py-1 font-medium text-sm transition-colors",
                "border border-border bg-background hover:bg-accent",
                "disabled:cursor-not-allowed disabled:opacity-50",
                "text-foreground"
              )}
              onClick={() => imageInputRef.current?.click()}
              title="Insert image"
              type="button"
            >
              Image
            </button>
            <input
              accept="image/jpeg,image/png,image/webp,image/gif"
              className="hidden"
              onChange={handleImageUpload}
              ref={imageInputRef}
              type="file"
            />
          </>
        )}
        {onVideoUpload && (
          <>
            <button
              className={cn(
                "rounded-md px-2 py-1 font-medium text-sm transition-colors",
                "border border-border bg-background hover:bg-accent",
                "disabled:cursor-not-allowed disabled:opacity-50",
                "text-foreground"
              )}
              onClick={() => videoInputRef.current?.click()}
              title="Insert video"
              type="button"
            >
              Video
            </button>
            <input
              accept="video/mp4,video/webm,video/quicktime"
              className="hidden"
              onChange={handleVideoUpload}
              ref={videoInputRef}
              type="file"
            />
          </>
        )}
      </div>
    </div>
  );
};

interface TiptapProps {
  initialContent: JSONContent;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onUpdate: (props: any) => void;
  onImageUpload?: (file: File) => Promise<string>;
  onVideoUpload?: (file: File) => Promise<string>;
}

export const Tiptap = ({
  initialContent,
  onUpdate,
  onImageUpload,
  onVideoUpload,
}: TiptapProps) => {
  const extensions = [
    Color.configure({ types: [TextStyle.name, ListItem.name] }),
    TextStyle.configure(),
    StarterKit.configure({
      bulletList: {
        keepMarks: true,
        keepAttributes: false,
      },
      orderedList: {
        keepMarks: true,
        keepAttributes: false,
      },
    }),
    Image.configure({
      HTMLAttributes: {
        class: "rounded-lg max-w-full h-auto",
      },
    }),
    Video,
  ];

  return (
    <>
      <EditorProvider
        content={initialContent}
        extensions={extensions}
        immediatelyRender={false}
        onUpdate={onUpdate}
        shouldRerenderOnTransaction={false}
        slotBefore={
          <MenuBar
            onImageUpload={onImageUpload}
            onVideoUpload={onVideoUpload}
          />
        }
      />
    </>
  );
};
