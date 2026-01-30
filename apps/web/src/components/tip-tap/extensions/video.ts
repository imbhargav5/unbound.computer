import { mergeAttributes, Node } from "@tiptap/core";

export interface VideoOptions {
  HTMLAttributes: Record<string, unknown>;
  allowFullscreen: boolean;
}

declare module "@tiptap/core" {
  interface Commands<ReturnType> {
    video: {
      setVideo: (options: { src: string; alt?: string }) => ReturnType;
    };
  }
}

export const Video = Node.create<VideoOptions>({
  name: "video",

  addOptions() {
    return {
      HTMLAttributes: {},
      allowFullscreen: true,
    };
  },

  group: "block",

  atom: true,

  addAttributes() {
    return {
      src: {
        default: null,
      },
      alt: {
        default: null,
      },
    };
  },

  parseHTML() {
    return [
      {
        tag: "video",
      },
    ];
  },

  renderHTML({ HTMLAttributes }) {
    return [
      "div",
      { class: "video-wrapper", style: "aspect-ratio: 131 / 100;" },
      [
        "video",
        mergeAttributes(this.options.HTMLAttributes, HTMLAttributes, {
          controls: true,
          class: "w-full h-full rounded-lg object-cover",
        }),
      ],
    ];
  },

  addCommands() {
    return {
      setVideo:
        (options) =>
        ({ commands }) =>
          commands.insertContent({
            type: this.name,
            attrs: options,
          }),
    };
  },
});
