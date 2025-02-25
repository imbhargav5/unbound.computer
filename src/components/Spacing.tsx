import { cn } from "@/utils/cn";
import { ReactNode } from "react";

/**
 * Base spacing scale used throughout the application
 *
 * These tokens ensure consistent spacing across the UI and should be used
 * instead of arbitrary values. Keys correspond to familiar Tailwind spacing units.
 *
 * @example
 * ```tsx
 * import { spaceTokens } from "@/components/Spacing";
 *
 * // Using in inline styles
 * <div style={{ padding: spaceTokens[4] }}>...</div>
 * ```
 */
export const spaceTokens = {
  0: "0px",
  px: "1px",
  0.5: "0.125rem", // 2px
  1: "0.25rem", // 4px
  2: "0.5rem", // 8px
  3: "0.75rem", // 12px
  4: "1rem", // 16px (base)
  5: "1.25rem", // 20px
  6: "1.5rem", // 24px
  8: "2rem", // 32px
  10: "2.5rem", // 40px
  12: "3rem", // 48px
  16: "4rem", // 64px
  20: "5rem", // 80px
  24: "6rem", // 96px
};

/**
 * Sizing tokens based on the same scale, extended with additional screen sizes
 *
 * Use these tokens for consistent widths, max-widths, heights, and other
 * dimensional properties throughout the application.
 *
 * @example
 * ```tsx
 * import { sizeTokens } from "@/components/Spacing";
 *
 * // Using in a component props
 * <Container maxWidth="3xl">...</Container>
 * ```
 */
export const sizeTokens = {
  ...spaceTokens,
  xs: "20rem", // 320px
  sm: "24rem", // 384px
  md: "28rem", // 448px
  lg: "32rem", // 512px
  xl: "36rem", // 576px
  "2xl": "42rem", // 672px
  "3xl": "48rem", // 768px
  "4xl": "56rem", // 896px
  "5xl": "64rem", // 1024px
  "6xl": "72rem", // 1152px
  "7xl": "80rem", // 1280px
};

// Common type for spacing components
type SpacingValue = keyof typeof spaceTokens | number | string;
type SpacingProps = {
  children?: ReactNode;
  className?: string;
};

/**
 * Helper to convert spacing values to CSS values
 *
 * @param space - A spacing value from tokens, a number (px), or a CSS string
 * @returns The CSS value as a string (e.g., "1rem", "16px", "2em")
 * @internal
 */
function getSpacingValue(space: SpacingValue): string {
  if (typeof space === "string") return space;
  return typeof space === "number"
    ? `${space}px`
    : spaceTokens[space as keyof typeof spaceTokens] || `${space}px`;
}

// Stack - Vertical spacing between elements
interface StackProps
  extends SpacingProps,
  React.HTMLAttributes<HTMLDivElement> {
  gap?: SpacingValue;
  align?: "start" | "center" | "end" | "stretch";
  justify?: "start" | "center" | "end" | "between" | "around" | "evenly";
}

/**
 * Stack - A vertical layout component with consistent spacing
 *
 * @component
 * @example
 * ```tsx
 * <Stack gap={4}>
 *   <Card>First item</Card>
 *   <Card>Second item</Card>
 *   <Card>Third item</Card>
 * </Stack>
 * ```
 *
 * @remarks
 * Use for vertically arranging components with consistent spacing.
 * Perfect for forms, card stacks, and vertical content layouts.
 * The gap prop accepts spacing tokens, numbers (px), or CSS strings.
 */
export function Stack({
  children,
  gap = 4,
  align = "stretch",
  justify = "start",
  className,
  ...props
}: StackProps) {
  const alignMap = {
    start: "items-start",
    center: "items-center",
    end: "items-end",
    stretch: "items-stretch",
  };

  const justifyMap = {
    start: "justify-start",
    center: "justify-center",
    end: "justify-end",
    between: "justify-between",
    around: "justify-around",
    evenly: "justify-evenly",
  };

  return (
    <div
      className={cn(
        "flex flex-col",
        alignMap[align],
        justifyMap[justify],
        className,
      )}
      style={{ gap: getSpacingValue(gap) }}
      {...props}
    >
      {children}
    </div>
  );
}

// HStack - Horizontal spacing between elements
interface HStackProps extends StackProps {
  wrap?: boolean;
}

/**
 * HStack - A horizontal layout component with consistent spacing
 *
 * @component
 * @example
 * ```tsx
 * <HStack gap={3} align="center">
 *   <Avatar />
 *   <div>
 *     <h3>User Name</h3>
 *     <p>Role: Admin</p>
 *   </div>
 * </HStack>
 * ```
 *
 * @remarks
 * Use for horizontally arranging components with consistent spacing.
 * Great for navigation items, button groups, and horizontal metadata.
 * The wrap prop allows content to wrap to multiple lines on smaller screens.
 */
export function HStack({
  children,
  gap = 4,
  align = "center",
  justify = "start",
  wrap = false,
  className,
  ...props
}: HStackProps) {
  const alignMap = {
    start: "items-start",
    center: "items-center",
    end: "items-end",
    stretch: "items-stretch",
  };

  const justifyMap = {
    start: "justify-start",
    center: "justify-center",
    end: "justify-end",
    between: "justify-between",
    around: "justify-around",
    evenly: "justify-evenly",
  };

  return (
    <div
      className={cn(
        "flex flex-row",
        wrap && "flex-wrap",
        alignMap[align],
        justifyMap[justify],
        className,
      )}
      style={{ gap: getSpacingValue(gap) }}
      {...props}
    >
      {children}
    </div>
  );
}

// Grid - Grid layout with consistent spacing
interface GridProps extends SpacingProps, React.HTMLAttributes<HTMLDivElement> {
  gap?: SpacingValue;
  columnGap?: SpacingValue;
  rowGap?: SpacingValue;
  columns?: number | { sm?: number; md?: number; lg?: number; xl?: number };
  align?: "start" | "center" | "end" | "stretch";
  justify?: "start" | "center" | "end" | "between" | "around" | "evenly";
}

/**
 * Grid - A responsive grid layout component with consistent spacing
 *
 * @component
 * @example
 * ```tsx
 * // Simple fixed column grid
 * <Grid columns={3} gap={4}>
 *   {items.map(item => <Card key={item.id}>{item.title}</Card>)}
 * </Grid>
 *
 * // Responsive grid with different columns at breakpoints
 * <Grid columns={{ sm: 1, md: 2, lg: 3, xl: 4 }} gap={6}>
 *   {items.map(item => <Card key={item.id}>{item.title}</Card>)}
 * </Grid>
 * ```
 *
 * @remarks
 * Use for creating grid layouts with responsive column counts.
 * Perfect for card grids, dashboards, galleries, and multi-column layouts.
 * Can specify different columns at various breakpoints for optimal responsive behavior.
 */
export function Grid({
  children,
  gap,
  columnGap,
  rowGap,
  columns = 1,
  align = "stretch",
  justify = "start",
  className,
  ...props
}: GridProps) {
  const alignMap = {
    start: "items-start",
    center: "items-center",
    end: "items-end",
    stretch: "items-stretch",
  };

  const justifyMap = {
    start: "justify-start",
    center: "justify-center",
    end: "justify-end",
    between: "justify-between",
    around: "justify-around",
    evenly: "justify-evenly",
  };

  // Prepare responsive columns
  let columnsClasses = "";
  if (typeof columns === "number") {
    columnsClasses = `grid-cols-${columns}`;
  } else {
    const { sm, md, lg, xl } = columns;
    if (sm) columnsClasses += ` sm:grid-cols-${sm}`;
    if (md) columnsClasses += ` md:grid-cols-${md}`;
    if (lg) columnsClasses += ` lg:grid-cols-${lg}`;
    if (xl) columnsClasses += ` xl:grid-cols-${xl}`;
  }

  return (
    <div
      className={cn(
        "grid",
        columnsClasses,
        alignMap[align],
        justifyMap[justify],
        className,
      )}
      style={{
        gap: gap !== undefined ? getSpacingValue(gap) : undefined,
        columnGap:
          columnGap !== undefined ? getSpacingValue(columnGap) : undefined,
        rowGap: rowGap !== undefined ? getSpacingValue(rowGap) : undefined,
      }}
      {...props}
    >
      {children}
    </div>
  );
}

// Spacer - Creates empty space
interface SpacerProps extends React.HTMLAttributes<HTMLDivElement> {
  size?: SpacingValue;
  axis?: "horizontal" | "vertical";
  grow?: boolean;
}

/**
 * Spacer - A component that creates empty space
 *
 * @component
 * @example
 * ```tsx
 * // Vertical spacing between components
 * <div>
 *   <Header />
 *   <Spacer size={8} />
 *   <MainContent />
 * </div>
 *
 * // Horizontal spacing between inline elements
 * <div className="flex">
 *   <Logo />
 *   <Spacer axis="horizontal" size={4} />
 *   <Navigation />
 * </div>
 *
 * // Flexible spacer that pushes elements apart
 * <div className="flex">
 *   <BackButton />
 *   <Spacer axis="horizontal" grow />
 *   <NextButton />
 * </div>
 * ```
 *
 * @remarks
 * Use to create precise spacing between elements or to push elements apart.
 * The grow prop is particularly useful in flex layouts to create justification.
 * Provides an explicit and semantic way to add spacing compared to margins.
 */
export function Spacer({
  size,
  axis = "vertical",
  grow = false,
  ...props
}: SpacerProps) {
  const width = axis === "horizontal" ? getSpacingValue(size || 4) : "1px";
  const height = axis === "vertical" ? getSpacingValue(size || 4) : "1px";

  return (
    <div
      style={{ width, height, flexGrow: grow ? 1 : 0 }}
      aria-hidden="true"
      {...props}
    />
  );
}

// Container - Centered container with max-width
interface ContainerProps
  extends SpacingProps,
  React.HTMLAttributes<HTMLDivElement> {
  maxWidth?: keyof typeof sizeTokens | string;
  padding?: SpacingValue;
  centered?: boolean;
}

/**
 * Container - A centered content container with consistent max-width
 *
 * @component
 * @example
 * ```tsx
 * // Default container
 * <Container>
 *   <h1>Page Title</h1>
 *   <p>Content goes here...</p>
 * </Container>
 *
 * // Customized container
 * <Container maxWidth="4xl" padding={6}>
 *   <article>...</article>
 * </Container>
 * ```
 *
 * @remarks
 * Use as a main content wrapper to maintain consistent widths throughout the app.
 * Perfect for page layouts, sections, and maintaining readable text widths.
 * The maxWidth prop accepts size tokens or custom values for flexibility.
 */
export function Container({
  children,
  maxWidth = "5xl",
  padding = 4,
  centered = true,
  className,
  ...props
}: ContainerProps) {
  const maxWidthValue =
    sizeTokens[maxWidth as keyof typeof sizeTokens] || maxWidth;

  return (
    <div
      className={cn(centered && "mx-auto", className)}
      style={{
        maxWidth: maxWidthValue,
        padding: getSpacingValue(padding),
      }}
      {...props}
    >
      {children}
    </div>
  );
}

// Section - Semantic section with consistent vertical spacing
interface SectionProps extends SpacingProps, React.HTMLAttributes<HTMLElement> {
  paddingY?: SpacingValue;
}

/**
 * Section - A semantic section with consistent vertical padding
 *
 * @component
 * @example
 * ```tsx
 * <Section>
 *   <h2>Features</h2>
 *   <FeatureGrid />
 * </Section>
 *
 * <Section paddingY={20}>
 *   <Testimonials />
 * </Section>
 * ```
 *
 * @remarks
 * Use to create clear vertical sections in your UI with consistent spacing.
 * Ideal for landing pages, content sections, and logical page divisions.
 * The semantic HTML section element improves document structure and accessibility.
 */
export function Section({
  children,
  paddingY = 12,
  className,
  ...props
}: SectionProps) {
  return (
    <section
      className={cn(className)}
      style={{
        paddingTop: getSpacingValue(paddingY),
        paddingBottom: getSpacingValue(paddingY),
      }}
      {...props}
    >
      {children}
    </section>
  );
}

// Box - Simple box with padding
interface BoxProps extends SpacingProps, React.HTMLAttributes<HTMLDivElement> {
  padding?: SpacingValue;
}

/**
 * Box - A simple container with consistent padding
 *
 * @component
 * @example
 * ```tsx
 * <Box padding={6}>
 *   <h3>Important Notice</h3>
 *   <p>This is highlighted content...</p>
 * </Box>
 * ```
 *
 * @remarks
 * Use as a generic container with consistent padding.
 * Ideal for card content, panels, and content blocks.
 * More minimal than Card with no predefined styling beyond padding.
 */
export function Box({ children, padding = 4, className, ...props }: BoxProps) {
  return (
    <div
      className={cn(className)}
      style={{ padding: getSpacingValue(padding) }}
      {...props}
    >
      {children}
    </div>
  );
}

// Center - Centers children horizontally and vertically
interface CenterProps
  extends SpacingProps,
  React.HTMLAttributes<HTMLDivElement> {
  inline?: boolean;
}

/**
 * Center - A component that centers children horizontally and vertically
 *
 * @component
 * @example
 * ```tsx
 * // Center content in a full-height section
 * <div className="h-screen">
 *   <Center>
 *     <LoginForm />
 *   </Center>
 * </div>
 *
 * // Inline centering for smaller UI elements
 * <Center inline>
 *   <Spinner size="sm" />
 *   <span>Loading...</span>
 * </Center>
 * ```
 *
 * @remarks
 * Use when you need perfect centering of content both horizontally and vertically.
 * Ideal for modals, empty states, loaders, and hero content.
 * The inline prop allows for centering inline elements without taking full width.
 */
export function Center({
  children,
  inline = false,
  className,
  ...props
}: CenterProps) {
  return (
    <div
      className={cn(
        inline ? "inline-flex" : "flex",
        "items-center justify-center",
        className,
      )}
      {...props}
    >
      {children}
    </div>
  );
}

// Divider - Horizontal or vertical divider line
interface DividerProps extends React.HTMLAttributes<HTMLHRElement> {
  orientation?: "horizontal" | "vertical";
  thickness?: number;
  color?: string;
  margin?: SpacingValue;
}

/**
 * Divider - A horizontal or vertical divider line
 *
 * @component
 * @example
 * ```tsx
 * // Horizontal divider between sections
 * <Section>First section content</Section>
 * <Divider margin={8} />
 * <Section>Second section content</Section>
 *
 * // Vertical divider between elements
 * <HStack>
 *   <Navigation />
 *   <Divider orientation="vertical" height="full" />
 *   <MainContent />
 * </HStack>
 * ```
 *
 * @remarks
 * Use to visually separate sections of content or UI elements.
 * Can be oriented horizontally (default) or vertically.
 * Customizable with thickness, color, and margin properties.
 */
export function Divider({
  orientation = "horizontal",
  thickness = 1,
  color = "currentColor",
  margin = 4,
  className,
  ...props
}: DividerProps) {
  const isVertical = orientation === "vertical";

  return (
    <hr
      className={cn(
        "border-0 opacity-20",
        isVertical ? "h-auto w-px" : "h-px w-auto",
        className,
      )}
      style={{
        backgroundColor: color,
        ...(isVertical
          ? {
            marginLeft: getSpacingValue(margin),
            marginRight: getSpacingValue(margin),
            height: "auto",
            alignSelf: "stretch",
          }
          : {
            marginTop: getSpacingValue(margin),
            marginBottom: getSpacingValue(margin),
          }),
        ...(thickness !== 1 && {
          [isVertical ? "width" : "height"]: `${thickness}px`,
        }),
      }}
      {...props}
    />
  );
}

// AspectRatio - A component that maintains a specific aspect ratio
interface AspectRatioProps
  extends SpacingProps,
  React.HTMLAttributes<HTMLDivElement> {
  ratio?: number;
}

/**
 * AspectRatio - A component that maintains a specific aspect ratio
 *
 * @component
 * @example
 * ```tsx
 * // 16:9 video embed
 * <AspectRatio ratio={16 / 9}>
 *   <iframe src="https://youtube.com/embed/..." />
 * </AspectRatio>
 *
 * // Square image container (1:1)
 * <AspectRatio ratio={1}>
 *   <img src="/image.jpg" alt="Square image" className="object-cover" />
 * </AspectRatio>
 * ```
 *
 * @remarks
 * Use to maintain consistent aspect ratios for media elements.
 * Perfect for responsive videos, image galleries, and cards with media.
 * Prevents layout shift by reserving the correct space before content loads.
 */
export function AspectRatio({
  children,
  ratio = 16 / 9,
  className,
  ...props
}: AspectRatioProps) {
  return (
    <div
      className={cn("relative w-full", className)}
      style={{ paddingBottom: `${(1 / ratio) * 100}%` }}
      {...props}
    >
      <div className="absolute inset-0">{children}</div>
    </div>
  );
}

/**
 * Spacing - Collection of spacing components and utilities
 *
 * @remarks
 * Provides a complete system for consistent spacing and layout.
 * Import individual components or use the Spacing object for access to all utilities.
 *
 * @example
 * ```tsx
 * import { Spacing } from "@/components/Spacing";
 *
 * function MyLayout() {
 *   return (
 *     <Spacing.Container>
 *       <Spacing.Stack gap={6}>
 *         <Header />
 *         <MainContent />
 *       </Spacing.Stack>
 *     </Spacing.Container>
 *   );
 * }
 * ```
 */
export const Spacing = {
  Stack,
  HStack,
  Grid,
  Spacer,
  Container,
  Section,
  Box,
  Center,
  Divider,
  AspectRatio,
  spaceTokens,
  sizeTokens,
};
