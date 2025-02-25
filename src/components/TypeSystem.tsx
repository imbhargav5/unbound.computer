import { cn } from "@/utils/cn";
import { Slot } from "@radix-ui/react-slot";
import { ComponentPropsWithoutRef, forwardRef } from "react";

/**
 * Comprehensive typography scale with responsive variants
 * This type scale provides a consistent typographic hierarchy across the application
 * with proper responsive behavior on different screen sizes.
 */
const typeScale = {
  // Hero/Feature text scales
  /**
   * Largest display text for hero sections and major feature highlights
   * Responsive: 6xl -> 7xl -> 8xl (mobile -> sm -> md)
   */
  display1: "text-6xl font-bold tracking-tight sm:text-7xl md:text-8xl",

  /**
   * Very large display text for section introductions and important callouts
   * Responsive: 5xl -> 6xl -> 7xl (mobile -> sm -> md)
   */
  display2: "text-5xl font-bold tracking-tight sm:text-6xl md:text-7xl",

  /**
   * Large display text for major section headings
   * Responsive: 4xl -> 5xl -> 6xl (mobile -> sm -> md)
   */
  display3: "text-4xl font-bold tracking-tight sm:text-5xl md:text-6xl",

  // Heading scales
  /**
   * Primary heading for page titles
   * Responsive: 3xl -> 4xl -> 5xl (mobile -> sm -> md)
   */
  h1: "text-3xl font-bold tracking-tight sm:text-4xl md:text-5xl",

  /**
   * Secondary heading for major sections
   * Responsive: 2xl -> 3xl (mobile -> sm)
   */
  h2: "text-2xl font-semibold tracking-tight sm:text-3xl",

  /**
   * Tertiary heading for subsections
   * Responsive: xl -> 2xl (mobile -> sm)
   */
  h3: "text-xl font-semibold tracking-tight sm:text-2xl",

  /**
   * Quaternary heading for content blocks
   * Responsive: lg -> xl (mobile -> sm)
   */
  h4: "text-lg font-semibold tracking-tight sm:text-xl",

  /**
   * Fifth-level heading for nested content
   * Responsive: base -> lg (mobile -> sm)
   */
  h5: "text-base font-semibold tracking-tight sm:text-lg",

  /**
   * Smallest heading, often used for special cases or UI elements
   * Responsive: sm -> base (mobile -> sm)
   */
  h6: "text-sm font-semibold tracking-tight sm:text-base",

  // Body text scales
  /**
   * Larger introductory paragraph text
   * Use for opening paragraphs, summaries, or highlighted content
   * Responsive: xl -> 2xl (mobile -> sm)
   */
  lead: "text-xl leading-7 sm:text-2xl sm:leading-8",

  /**
   * Standard body text for main content
   * Use for the majority of paragraph text
   */
  body: "text-base leading-7",

  /**
   * Smaller text for less emphasized content
   * Use for secondary information, metadata, or UI labels
   */
  small: "text-sm leading-6",

  /**
   * Smallest text for auxiliary information
   * Use for footnotes, captions, or legal text
   */
  xs: "text-xs leading-5",

  // Specialized text styles
  /**
   * Small uppercase text often used above headings
   * Perfect for category labels, section markers, or text that needs emphasis without size
   */
  overline: "text-xs font-medium uppercase tracking-widest",

  /**
   * Styled text for image captions, footnotes, and attributions
   * Slightly muted and italicized for visual distinction
   */
  caption: "text-xs italic leading-5 text-muted-foreground",

  /**
   * Subdued text for secondary information
   * Use for descriptions, helper text, or less important content
   */
  subtle: "text-sm text-muted-foreground leading-6",

  /**
   * Monospaced text for inline code snippets
   * Features a subtle background for better visibility
   */
  code: "font-mono text-sm bg-muted px-1.5 py-0.5 rounded",

  /**
   * Styled text for quotations and testimonials
   * Italicized and slightly larger with proper responsive scaling
   */
  quote: "text-lg italic leading-7 sm:text-xl sm:leading-8",

  /**
   * Optimized text for form labels
   * Compact with no line height to reduce excess spacing in forms
   */
  label: "text-sm font-medium leading-none",
};

// Common interface for all text components
interface TextProps extends ComponentPropsWithoutRef<"span"> {
  asChild?: boolean;
  as?: React.ElementType;
}

/**
 * Display1 - Largest display text component
 *
 * @component
 * @example
 * ```tsx
 * <Display1>Powerful Features</Display1>
 * ```
 *
 * @remarks
 * Use for main hero titles, landing page headlines, or the most important heading on a page.
 * Scales dramatically across breakpoints for maximum impact on larger screens.
 */
export const Display1 = forwardRef<HTMLHeadingElement, TextProps>(
  ({ className, as = "h1", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp
        ref={ref}
        className={cn("scroll-m-20", typeScale.display1, className)}
        {...props}
      />
    );
  },
);
Display1.displayName = "Display1";

/**
 * Display2 - Large display text component
 *
 * @component
 * @example
 * ```tsx
 * <Display2>About Our Platform</Display2>
 * ```
 *
 * @remarks
 * Use for secondary hero titles, major section headlines, or important feature highlights.
 * Balances impact with readability across device sizes.
 */
export const Display2 = forwardRef<HTMLHeadingElement, TextProps>(
  ({ className, as = "h1", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp
        ref={ref}
        className={cn("scroll-m-20", typeScale.display2, className)}
        {...props}
      />
    );
  },
);
Display2.displayName = "Display2";

/**
 * Display3 - Medium display text component
 *
 * @component
 * @example
 * ```tsx
 * <Display3>Key Benefits</Display3>
 * ```
 *
 * @remarks
 * Use for tertiary displays, major section titles, or when you need impact but not the
 * full size of larger display components. Works well for feature section headings.
 */
export const Display3 = forwardRef<HTMLHeadingElement, TextProps>(
  ({ className, as = "h1", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp
        ref={ref}
        className={cn("scroll-m-20", typeScale.display3, className)}
        {...props}
      />
    );
  },
);
Display3.displayName = "Display3";

/**
 * Heading1 - Primary heading component (H1)
 *
 * @component
 * @example
 * ```tsx
 * <Heading1>Projects Dashboard</Heading1>
 * ```
 *
 * @remarks
 * Use for page titles and main content headings. Each page should typically
 * have only one H1 for proper document structure and accessibility.
 */
export const Heading1 = forwardRef<HTMLHeadingElement, TextProps>(
  ({ className, as = "h1", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp
        ref={ref}
        className={cn("scroll-m-20", typeScale.h1, className)}
        {...props}
      />
    );
  },
);
Heading1.displayName = "Heading1";

/**
 * Heading2 - Secondary heading component (H2)
 *
 * @component
 * @example
 * ```tsx
 * <Heading2>Recent Activity</Heading2>
 * ```
 *
 * @remarks
 * Use for major section headings within a page. Includes top margin for spacing
 * from preceding content, with a first-child exception to avoid extra space.
 */
export const Heading2 = forwardRef<HTMLHeadingElement, TextProps>(
  ({ className, as = "h2", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp
        ref={ref}
        className={cn("scroll-m-20 mt-10 first:mt-0", typeScale.h2, className)}
        {...props}
      />
    );
  },
);
Heading2.displayName = "Heading2";

/**
 * Heading3 - Tertiary heading component (H3)
 *
 * @component
 * @example
 * ```tsx
 * <Heading3>User Statistics</Heading3>
 * ```
 *
 * @remarks
 * Use for subsection headings within major sections. Includes appropriate spacing
 * with a first-child exception for cleaner layout in nested content.
 */
export const Heading3 = forwardRef<HTMLHeadingElement, TextProps>(
  ({ className, as = "h3", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp
        ref={ref}
        className={cn("scroll-m-20 mt-8 first:mt-0", typeScale.h3, className)}
        {...props}
      />
    );
  },
);
Heading3.displayName = "Heading3";

/**
 * Heading4 - Quaternary heading component (H4)
 *
 * @component
 * @example
 * ```tsx
 * <Heading4>Payment Methods</Heading4>
 * ```
 *
 * @remarks
 * Use for subheadings within sections, card titles, or widget headers.
 * Maintains visual hierarchy with appropriate spacing.
 */
export const Heading4 = forwardRef<HTMLHeadingElement, TextProps>(
  ({ className, as = "h4", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp
        ref={ref}
        className={cn("scroll-m-20 mt-8 first:mt-0", typeScale.h4, className)}
        {...props}
      />
    );
  },
);
Heading4.displayName = "Heading4";

/**
 * Heading5 - Fifth-level heading component (H5)
 *
 * @component
 * @example
 * ```tsx
 * <Heading5>Billing Information</Heading5>
 * ```
 *
 * @remarks
 * Use for minor section titles, form section headers, or when you need a heading
 * that's only slightly more prominent than body text.
 */
export const Heading5 = forwardRef<HTMLHeadingElement, TextProps>(
  ({ className, as = "h5", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp
        ref={ref}
        className={cn("scroll-m-20 mt-8 first:mt-0", typeScale.h5, className)}
        {...props}
      />
    );
  },
);
Heading5.displayName = "Heading5";

/**
 * Heading6 - Smallest heading component (H6)
 *
 * @component
 * @example
 * ```tsx
 * <Heading6>Card Details</Heading6>
 * ```
 *
 * @remarks
 * Use for the smallest section headings, compact UI elements, or situations where
 * you need semantic heading structure but minimal visual distinction.
 */
export const Heading6 = forwardRef<HTMLHeadingElement, TextProps>(
  ({ className, as = "h6", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp
        ref={ref}
        className={cn("scroll-m-20 mt-8 first:mt-0", typeScale.h6, className)}
        {...props}
      />
    );
  },
);
Heading6.displayName = "Heading6";

/**
 * Lead - Larger introductory text component
 *
 * @component
 * @example
 * ```tsx
 * <Lead>Discover our powerful suite of tools designed to simplify your workflow.</Lead>
 * ```
 *
 * @remarks
 * Use for opening paragraphs, important summaries, or highlighted content.
 * Creates visual distinction from standard body text to draw attention to key messaging.
 */
export const Lead = forwardRef<HTMLParagraphElement, TextProps>(
  ({ className, as = "p", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp ref={ref} className={cn(typeScale.lead, className)} {...props} />
    );
  },
);
Lead.displayName = "Lead";

/**
 * Text - Standard body text component
 *
 * @component
 * @example
 * ```tsx
 * <Text>Our platform provides comprehensive analytics and reporting features.</Text>
 * ```
 *
 * @remarks
 * Use for the majority of paragraph text in your application.
 * Includes margin top for consecutive paragraphs while avoiding margins on the first paragraph.
 */
export const Text = forwardRef<HTMLParagraphElement, TextProps>(
  ({ className, as = "p", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp
        ref={ref}
        className={cn("&:not(:first-child):mt-6", typeScale.body, className)}
        {...props}
      />
    );
  },
);
Text.displayName = "Text";

/**
 * SmallText - Smaller text component
 *
 * @component
 * @example
 * ```tsx
 * <SmallText>Last updated: June 2023</SmallText>
 * ```
 *
 * @remarks
 * Use for secondary information, metadata, timestamps, or when space is limited.
 * Provides enough contrast with body text to create visual hierarchy without being too small.
 */
export const SmallText = forwardRef<HTMLElement, TextProps>(
  ({ className, as = "small", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp ref={ref} className={cn(typeScale.small, className)} {...props} />
    );
  },
);
SmallText.displayName = "SmallText";

/**
 * XSmallText - Extra small text component
 *
 * @component
 * @example
 * ```tsx
 * <XSmallText>Terms and conditions apply.</XSmallText>
 * ```
 *
 * @remarks
 * Use for footnotes, legal text, captions, or other auxiliary content that should
 * be present but minimally intrusive. Be careful with readability at this size.
 */
export const XSmallText = forwardRef<HTMLElement, TextProps>(
  ({ className, as = "span", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp ref={ref} className={cn(typeScale.xs, className)} {...props} />
    );
  },
);
XSmallText.displayName = "XSmallText";

/**
 * Overline - Small uppercase text component
 *
 * @component
 * @example
 * ```tsx
 * <Overline>New Feature</Overline>
 * ```
 *
 * @remarks
 * Use for category labels, eyebrows (text above headings), badges, or other text
 * that needs emphasis through text treatment rather than size. The uppercase and
 * tracking (letter-spacing) combination creates a distinctive look.
 */
export const Overline = forwardRef<HTMLElement, TextProps>(
  ({ className, as = "span", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp
        ref={ref}
        className={cn(typeScale.overline, className)}
        {...props}
      />
    );
  },
);
Overline.displayName = "Overline";

/**
 * Caption - Small, italicized text component
 *
 * @component
 * @example
 * ```tsx
 * <Caption>Photo by Jane Smith, 2023</Caption>
 * ```
 *
 * @remarks
 * Ideal for image captions, figure descriptions, source attributions, and other
 * supporting text. The italics and muted color help visually separate it from main content.
 */
export const Caption = forwardRef<HTMLElement, TextProps>(
  ({ className, as = "figcaption", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp ref={ref} className={cn(typeScale.caption, className)} {...props} />
    );
  },
);
Caption.displayName = "Caption";

/**
 * Subtle - Muted text component
 *
 * @component
 * @example
 * ```tsx
 * <Subtle>Additional information is available in the documentation.</Subtle>
 * ```
 *
 * @remarks
 * Use for helper text, descriptions, or content that should be visually secondary.
 * The muted color creates visual distinction without requiring a size change.
 */
export const Subtle = forwardRef<HTMLParagraphElement, TextProps>(
  ({ className, as = "p", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp ref={ref} className={cn(typeScale.subtle, className)} {...props} />
    );
  },
);
Subtle.displayName = "Subtle";

/**
 * CodeText - Monospaced code text component
 *
 * @component
 * @example
 * ```tsx
 * <CodeText>npm install @nextbase/ui</CodeText>
 * ```
 *
 * @remarks
 * Perfect for inline code snippets, terminal commands, file paths, or technical values.
 * The monospace font, subtle background, and rounded corners improve readability.
 */
export const CodeText = forwardRef<HTMLElement, TextProps>(
  ({ className, as = "code", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp ref={ref} className={cn(typeScale.code, className)} {...props} />
    );
  },
);
CodeText.displayName = "CodeText";

/**
 * Quote - Styled blockquote component
 *
 * @component
 * @example
 * ```tsx
 * <Quote>The future belongs to those who believe in the beauty of their dreams.</Quote>
 * ```
 *
 * @remarks
 * Use for testimonials, pull quotes, or cited material. Features a distinctive
 * left border and italic styling to set it apart from regular body content.
 */
export const Quote = forwardRef<HTMLQuoteElement, TextProps>(
  ({ className, as = "blockquote", asChild, ...props }, ref) => {
    const Comp = asChild ? Slot : as;
    return (
      <Comp
        ref={ref}
        className={cn(
          "mt-6 border-l-2 border-slate-300 pl-6 dark:border-slate-600",
          typeScale.quote,
          className,
        )}
        {...props}
      />
    );
  },
);
Quote.displayName = "Quote";

/**
 * Label - Form label text component
 *
 * @component
 * @example
 * ```tsx
 * <Label htmlFor="email">Email Address</Label>
 * ```
 *
 * @remarks
 * Specifically designed for form field labels with appropriate sizing and weight.
 * The absence of line-height helps create more compact form layouts.
 */
export const Label = forwardRef<
  HTMLLabelElement,
  TextProps & { htmlFor?: string }
>(({ className, as = "label", asChild, ...props }, ref) => {
  const Comp = asChild ? Slot : as;
  return (
    <Comp ref={ref} className={cn(typeScale.label, className)} {...props} />
  );
});
Label.displayName = "Label";

/**
 * TypeSystem - Collection of all typography components
 *
 * @remarks
 * Provides a complete type system with a consistent hierarchy and responsive behavior.
 * Import individual components or use the TypeSystem object for access to all components.
 */
export const TypeSystem = {
  Display1,
  Display2,
  Display3,
  Heading1,
  Heading2,
  Heading3,
  Heading4,
  Heading5,
  Heading6,
  Lead,
  Text,
  SmallText,
  XSmallText,
  Overline,
  Caption,
  Subtle,
  CodeText,
  Quote,
  Label,
};

/**
 * T - Shorthand alias for TypeSystem
 *
 * @example
 * ```tsx
 * import { T } from "@/components/TypeSystem";
 *
 * function MyComponent() {
 *   return (
 *     <div>
 *       <T.Heading1>Welcome to our platform</T.Heading1>
 *       <T.Text>Start exploring our features...</T.Text>
 *     </div>
 *   );
 * }
 * ```
 */
export const T = TypeSystem;
