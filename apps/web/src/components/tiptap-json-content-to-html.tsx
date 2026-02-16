import { Color } from "@tiptap/extension-color";
import { ListItem } from "@tiptap/extension-list-item";
import { TextStyle } from "@tiptap/extension-text-style";
import { generateHTML } from "@tiptap/html";
import { StarterKit } from "@tiptap/starter-kit";
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
];

export function TiptapJSONContentToHTML({
  jsonContent,
}: {
  jsonContent: unknown;
}) {
  let validContent: Record<string, unknown> = {};
  if (typeof jsonContent === "string") {
    try {
      const parsed = JSON.parse(jsonContent);
      if (parsed && typeof parsed === "object") {
        validContent = parsed as Record<string, unknown>;
      }
    } catch {
      validContent = {};
    }
  } else if (jsonContent && typeof jsonContent === "object") {
    validContent = jsonContent as Record<string, unknown>;
  }
  if (Object.keys(validContent).length === 0) {
    return <div />;
  }
  return (
    <div
      dangerouslySetInnerHTML={{
        __html: generateHTML(validContent, extensions),
      }}
    />
  );
}
