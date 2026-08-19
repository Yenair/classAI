---
name: Academic Focus
colors:
  surface: '#131315'
  surface-dim: '#131315'
  surface-bright: '#39393b'
  surface-container-lowest: '#0e0e10'
  surface-container-low: '#1b1b1d'
  surface-container: '#201f21'
  surface-container-high: '#2a2a2c'
  surface-container-highest: '#353437'
  on-surface: '#e5e1e4'
  on-surface-variant: '#c5c5d3'
  inverse-surface: '#e5e1e4'
  inverse-on-surface: '#303032'
  outline: '#8f909d'
  outline-variant: '#454652'
  surface-tint: '#b8c3ff'
  primary: '#b8c3ff'
  on-primary: '#0b267e'
  primary-container: '#8fa3ff'
  on-primary-container: '#1e358b'
  inverse-primary: '#4358ae'
  secondary: '#d7baff'
  on-secondary: '#401578'
  secondary-container: '#5a3392'
  on-secondary-container: '#cba8ff'
  tertiary: '#6bd2ff'
  on-tertiary: '#003547'
  tertiary-container: '#00b6ea'
  on-tertiary-container: '#004358'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#dde1ff'
  primary-fixed-dim: '#b8c3ff'
  on-primary-fixed: '#001355'
  on-primary-fixed-variant: '#2a3f95'
  secondary-fixed: '#eddcff'
  secondary-fixed-dim: '#d7baff'
  on-secondary-fixed: '#280056'
  on-secondary-fixed-variant: '#583190'
  tertiary-fixed: '#bee9ff'
  tertiary-fixed-dim: '#6bd2ff'
  on-tertiary-fixed: '#001f2a'
  on-tertiary-fixed-variant: '#004d65'
  background: '#131315'
  on-background: '#e5e1e4'
  surface-variant: '#353437'
typography:
  display-lg:
    fontFamily: Work Sans
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 48px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Work Sans
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Work Sans
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  body-xl:
    fontFamily: Work Sans
    fontSize: 20px
    fontWeight: '400'
    lineHeight: 30px
  body-lg:
    fontFamily: Work Sans
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  label-lg:
    fontFamily: Work Sans
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: 0.05em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 8px
  container-padding: 24px
  card-gap: 16px
  touch-target-min: 48px
  max-width-content: 800px
---

## Brand & Style

This design system is built for the Nigerian academic context, prioritizing extreme clarity, cognitive ease, and high accessibility. The brand personality is authoritative yet encouraging—acting as a reliable "Academic Partner." 

The visual style is a fusion of **Minimalism** and a **Tactile "Deck of Cards"** metaphor. By utilizing full-screen tiles and a card-based layout, the UI minimizes distraction and focuses the user's attention on one educational objective at a time. The aesthetic is clean and professional, using depth and scale rather than decorative elements to signal importance. The dark theme reduces eye strain during long study or lesson-planning sessions.

## Colors

The palette is anchored in a deep, nocturnal neutral base to ensure maximum contrast for vibrant accents. 

- **Primary (Blue):** A high-visibility, slightly desaturated blue used for primary actions and "unlocked" states.
- **Secondary (Purple):** Reserved for academic milestones, lesson indicators, and active navigation states.
- **Tertiary (Cyan):** Used sparingly for information highlights and success states.
- **Neutral:** A tiered system of near-blacks and deep grays creates the "stacking" effect for the deck-of-cards metaphor.

All color combinations must pass WCAG AAA standards for text contrast. Use white for most body text on dark backgrounds to ensure legibility in varying light conditions common in classroom settings.

## Typography

This system uses **Work Sans** exclusively. Its grotesque, neutral terminal endings and generous x-height make it exceptionally readable on low-resolution screens. 

To maintain high accessibility:
- **Simplify:** Use only three weights (400, 600, 700). 
- **Scale:** Sizes are intentionally larger than standard web defaults to accommodate varied vision levels.
- **Rhythm:** Line heights are set to 1.5x for body text to prevent "line-jumping" during reading.
- **Hierarchy:** Use font weight and color (High Contrast vs Muted) rather than complex font pairings to distinguish between headers and metadata.

## Layout & Spacing

The layout follows a **Fluid Grid** with strict constraints to maintain a "focused content" view. 

- **Deck of Cards Metaphor:** Content is encapsulated in full-width or large-scale cards. On mobile, these tiles should ideally take up 80-90% of the viewport height to encourage focus.
- **Safe Zones:** High horizontal margins (24px+) on desktop keep the reading line length within the 50-75 character "sweet spot" for academic comprehension.
- **Touch-First:** All interactive elements (buttons, inputs, toggles) must have a minimum hit area of 48x48px, even if the visual element is smaller.
- **Vertical Rhythm:** A strict 8px baseline grid ensures consistent alignment of text and components.

## Elevation & Depth

Depth is achieved through **Tonal Layers** rather than heavy shadows, ensuring the UI remains performant on a wide range of hardware.

1.  **Canvas (Level 0):** The base background `#0A0A0B`.
2.  **Surface (Level 1):** Large container cards `#1E1E22`.
3.  **Active/Elevated (Level 2):** Hovered items or focused inputs `#2A2A2E`.
4.  **Floating (Level 3):** Modals or temporary alerts use a soft, low-opacity primary-tinted shadow (0px 8px 24px rgba(143, 163, 255, 0.15)) to indicate they are at the top of the stack.

Structural borders (1px solid) are used only when two surfaces of the same color must meet, otherwise, use tonal shifts to define boundaries.

## Shapes

The shape language uses a **Rounded** (0.5rem) corner radius for most standard components. This strikes a balance between the serious nature of academia and the approachability of a digital partner.

- **Standard Cards:** 0.5rem (8px).
- **Buttons & Large Chips:** 1rem (16px) to emphasize touchability.
- **Outer Containers:** When cards are nested, the outer container should have a larger radius (1.5rem) to maintain visual harmony.
- **Inputs:** 0.5rem (8px) for a structured, professional feel.

## Components

### Buttons
- **Primary:** Solid `#8FA3FF` fill with `#000000` text. High-visibility and unmistakable.
- **Secondary:** Outline-only with 2px stroke of Primary or Secondary accent.
- **Tertiary:** Text-only with an icon, used for less frequent actions like "Back" or "Cancel."

### Cards (Full-screen Tiles)
- Cards should have a consistent padding of `24px` (desktop) or `16px` (mobile). 
- In the "Lesson Editor," cards act as distinct blocks (Introduction, Development, Conclusion) that can be collapsed to navigate the "deck."

### Input Fields
- Inputs must have high-contrast labels (Label-lg). 
- Focus states are indicated by a 2px Primary color border and a subtle glow.

### Chips & Tags
- Used for metadata like "JSS 2" or "English Studies." 
- Use semi-transparent versions of accent colors (e.g., Primary at 15% opacity) with solid-colored text to maintain hierarchy without competing with primary buttons.

### Icons
- Icons must be **Literal and Bold**. Use thick strokes (2px minimum). Avoid abstract metaphors; use a book for lessons, a clock for duration, and a checkmark for completion.