---
name: ClassAI Core
colors:
  surface: '#f8f9ff'
  surface-dim: '#d9dae0'
  surface-bright: '#f8f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f2f3f9'
  surface-container: '#ededf3'
  surface-container-high: '#e7e8ee'
  surface-container-highest: '#e1e2e8'
  on-surface: '#191c20'
  on-surface-variant: '#414750'
  inverse-surface: '#2e3035'
  inverse-on-surface: '#eff0f6'
  outline: '#727781'
  outline-variant: '#c1c7d2'
  surface-tint: '#1b61a0'
  primary: '#115b9b'
  on-primary: '#ffffff'
  primary-container: '#3674b5'
  on-primary-container: '#f5f7ff'
  inverse-primary: '#a1c9ff'
  secondary: '#4b53ba'
  on-secondary: '#ffffff'
  secondary-container: '#8c94ff'
  on-secondary-container: '#1e258f'
  tertiary: '#344ebf'
  on-tertiary: '#ffffff'
  tertiary-container: '#5068d9'
  on-tertiary-container: '#f8f6ff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d2e4ff'
  primary-fixed-dim: '#a1c9ff'
  on-primary-fixed: '#001c37'
  on-primary-fixed-variant: '#004880'
  secondary-fixed: '#e0e0ff'
  secondary-fixed-dim: '#bec2ff'
  on-secondary-fixed: '#00026c'
  on-secondary-fixed-variant: '#323aa1'
  tertiary-fixed: '#dde1ff'
  tertiary-fixed-dim: '#b9c3ff'
  on-tertiary-fixed: '#001257'
  on-tertiary-fixed-variant: '#1d3aac'
  background: '#f8f9ff'
  on-background: '#191c20'
  surface-variant: '#e1e2e8'
typography:
  display-lg:
    fontFamily: Open Sans
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Open Sans
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Open Sans
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
  title-lg:
    fontFamily: Open Sans
    fontSize: 22px
    fontWeight: '500'
    lineHeight: 28px
  body-lg:
    fontFamily: Albert Sans
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Albert Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-lg:
    fontFamily: Open Sans
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: 0.1px
  label-md:
    fontFamily: Open Sans
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  base: 8px
  margin-mobile: 16px
  margin-tablet: 24px
  gutter: 16px
  touch-target: 48px
---

## Brand & Style
The design system is engineered for the Nigerian educational landscape, prioritizing reliability and professional empowerment. The brand persona is that of a "Trusted Academic Partner"—stable, authoritative, and deeply functional. 

The aesthetic follows a **Modern Corporate** style influenced by Material 3, stripped of superfluous decoration to ensure peak performance on low-end hardware. The UI evokes a sense of order and clarity, utilizing high-contrast elements to ensure readability in varying classroom lighting conditions. The focus is on utility, using clear structural hierarchy to reduce cognitive load for educators managing large classrooms.

## Colors
This design system utilizes a refreshed palette designed for clarity and focus.
- **Primary (Blue):** A stable, professional blue (`#3674b5`) used for critical branding, primary actions, and top-level navigation.
- **Secondary (Navy):** A deep navy blue (`#00027e`) used for secondary actions and high-priority organizational elements, grounding the interface with authority.
- **Tertiary (Ocean Blue):** A vibrant yet professional blue-tone (`#00289e`) used for specialized academic accents, highlighting specific educational categories or student achievements.
- **Neutral/Surface:** Standard Material 3 neutral tones provide a clean, accessible backdrop that ensures content remains the focal point.

## Typography
Typography is optimized for legibility and distinct functional roles across various screen types.
- **Headlines:** Uses **Open Sans** for a friendly yet professional and clear appearance at large sizes.
- **Body:** Uses **Albert Sans** for superior readability in long-form text and data-heavy tables on mobile screens.
- **Labels:** Uses **Open Sans** for UI metadata and small-scale labels, ensuring a cohesive and functional appearance that aligns with the headline style.
- **Minimum Standards:** Body text never drops below 16px to accommodate diverse vision needs and screen quality.
- **Hierarchy:** Bold weights are used sparingly for headlines to maintain a professional, academic tone.

## Layout & Spacing
The design system employs a **Fluid Grid** with fixed logical breakpoints for mobile and tablet. 
- **Mobile:** 4-column grid with 16px side margins. Uses a `BottomNavigationBar` for primary reachability.
- **Tablet:** 12-column grid with 24px side margins. Uses a `NavigationRail` on the left to maximize vertical space for educational content.
- **Rhythm:** An 8px linear scale governs all padding and margins. 
- **Touch Targets:** All interactive elements (buttons, chips, inputs) maintain a minimum height of 48px to ensure ease of use in active classroom environments.

## Elevation & Depth
In alignment with Material 3, depth is conveyed through **Tonal Layers** rather than heavy shadows. 
- **Surface Level 0:** Background (White).
- **Surface Level 1 (Elevated):** Cards and Modal sheets use a subtle tonal fill or a very soft 2dp shadow to distinguish them from the background.
- **Sync Indicators:** Use flat color fills to indicate status, avoiding elevation to ensure they feel like integrated system signals rather than interactive buttons.
- **Active States:** Subtle tonal overlays (Primary at 8% opacity) indicate hover or focus states.

## Shapes
The shape language is **Soft (0.25rem)**, creating a professional and organized interface that feels precise and efficient.
- **Buttons & Inputs:** Use the base 0.25rem (4px) radius for a sharp, modern, and technical appearance.
- **Cards & Containers:** Use 0.5rem (8px) for a clear and structural separation of content.
- **Chips:** Utilize a semi-pill shape (full radius) to differentiate them from actionable buttons.
- **Material Icons:** Strictly use the "Rounded" or "Filled" Material Icon set.

## Components
- **Sync Status Indicators:** 
    - *Gray:* Offline mode.
    - *Blue (#3674b5):* Syncing in progress.
    - *Navy (#00027e):* Specialized status or high-priority educational content.
    - *Red:* Sync error/Action required.
- **Buttons:**
    - *Primary:* Filled with Blue (#3674b5), high-contrast text, using a 0.25rem corner radius.
    - *SegmentedButtons:** Used for toggling views (e.g., Attendance vs. Grades), following M3 specifications.
- **Chips:**
    - *FilterChips:* Used for sorting student lists or subjects.
    - *ActionChips:* Used for quick classroom actions (e.g., "Mark All Present").
- **Inputs:** Outlined text fields with persistent labels and 0.25rem corner radius to ensure context is never lost during data entry.
- **Navigation:**
    - *Phone:* `BottomNavigationBar` with icons and labels for all destinations.
    - *Tablet:* `NavigationRail` providing a persistent anchor for quick switching between classes.
- **Cards:** Used for individual student profiles or lesson modules, using Level 1 elevation and 0.5rem corner radius for clean separation.