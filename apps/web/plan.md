# EditChangelogForm UI Improvement Plan

## Current Issues
1. **Featured media upload area is too large** - Takes up significant vertical space with 16:9 aspect ratio
2. **Sidebar is not useful** - Contains only AuthorsSelect in a 384px (w-96) column
3. **Overall form feels spread out** - Too much whitespace and visual noise

---

## Layout Option A: Compact Single Column

Remove the sidebar entirely and use a single-column layout with a more compact design.

**Changes:**
- Remove sidebar, make AuthorsSelect part of the main form
- Reduce media preview from 16:9 to a smaller thumbnail (e.g., 200px height max)
- Use horizontal layout for metadata fields (version + status inline)
- Keep tags section compact with wrapping badges

**Structure:**
```
┌─────────────────────────────────────────────────┐
│ [Media Thumbnail 200px] │ Media Alt Text Input  │
├─────────────────────────────────────────────────┤
│ Version: [____]  Status: [____]  Authors: [___] │
├─────────────────────────────────────────────────┤
│ Tags: [+New Feature] [+AI] [+UI] ...            │
├─────────────────────────────────────────────────┤
│ Title: [________________________________]       │
├─────────────────────────────────────────────────┤
│ Content (Tiptap Editor)                         │
│                                                 │
├─────────────────────────────────────────────────┤
│ Technical Details (collapsible)                 │
├─────────────────────────────────────────────────┤
│                              [Update Changelog] │
└─────────────────────────────────────────────────┘
```

**Pros:**
- Much more compact
- No wasted sidebar space
- Faster to scan and fill out

**Cons:**
- Media preview is smaller (less visual feedback)

---

## Layout Option B: Collapsible Sections with Tabbed Metadata

Use collapsible accordion sections to hide complexity until needed.

**Changes:**
- Media section collapsed by default, shows small preview when media exists
- Metadata (version, tags, status, authors) in a collapsed "Settings" accordion
- Main focus on Title + Content which are always visible
- Technical details remains collapsible at bottom

**Structure:**
```
┌─────────────────────────────────────────────────┐
│ ▶ Featured Media [thumbnail if exists]          │
├─────────────────────────────────────────────────┤
│ ▶ Settings (Version, Tags, Status, Authors)     │
├─────────────────────────────────────────────────┤
│ Title: [________________________________]       │
├─────────────────────────────────────────────────┤
│ Content (Tiptap Editor)                         │
│                                                 │
│                                                 │
├─────────────────────────────────────────────────┤
│ ▶ Technical Details                             │
├─────────────────────────────────────────────────┤
│                              [Update Changelog] │
└─────────────────────────────────────────────────┘
```

**Pros:**
- Very clean, focuses on content
- Settings hidden until needed
- Scales well for future fields

**Cons:**
- More clicks to access all fields
- May be harder to see all settings at once

---

## Layout Option C: Two-Column with Integrated Sidebar (Recommended)

Keep two-column layout but make it more balanced and useful.

**Changes:**
- Reduce main form max-width, give sidebar more purpose
- Move media upload to sidebar with compact square preview
- Keep Title + Content + Technical Details in main area
- Sidebar contains: Media, Version, Tags, Status, Authors (all metadata)

**Structure:**
```
┌──────────────────────────────────┬──────────────────┐
│ Title: [____________________]    │ [Media Upload]   │
├──────────────────────────────────┤ 1:1 aspect ratio │
│ Content (Tiptap Editor)          │ smaller preview  │
│                                  ├──────────────────┤
│                                  │ Alt: [________]  │
│                                  ├──────────────────┤
│                                  │ Version: [____]  │
│                                  ├──────────────────┤
│                                  │ Status: [______] │
├──────────────────────────────────┼──────────────────┤
│ ▶ Technical Details              │ Tags:            │
│                                  │ [+New] [+AI]     │
│                                  ├──────────────────┤
│                                  │ Authors:         │
│                                  │ [Select authors] │
├──────────────────────────────────┴──────────────────┤
│                              [Update Changelog]     │
└─────────────────────────────────────────────────────┘
```

**Pros:**
- Clear separation: Content (left) vs Metadata (right)
- Media preview is visible but compact
- All fields visible without collapsing
- Sidebar now has clear purpose

**Cons:**
- Still uses horizontal space for sidebar

---

## My Recommendation

**Option C (Two-Column with Integrated Sidebar)** provides the best balance:
- Maintains visual preview of media without dominating the form
- Groups all metadata logically in the sidebar
- Keeps the primary focus on title and content editing
- No need for collapsible sections that hide important fields

The key improvements from current:
1. Media preview shrinks from 16:9 to 1:1 (square) and moves to sidebar
2. Version, Status, Tags all move to sidebar alongside Authors
3. Main column focuses purely on content (Title, Tiptap, Technical Details)
4. Sidebar width reduced from w-96 (384px) to w-80 (320px)

---

## Please select your preferred option:
- **A**: Compact Single Column
- **B**: Collapsible Sections
- **C**: Two-Column with Integrated Sidebar (Recommended)
