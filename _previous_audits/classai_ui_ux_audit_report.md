# ClassAI — Complete UI/UX Audit Report

**Date:** 2026-05-25  
**Scope:** Full source code audit of all UI screens, widgets, providers, and services  
**Method:** Manual inspection of every screen, widget, provider, and service file

---

## Issue Table

| # | Priority | Category | File | Line(s) | Issue | Suggested Fix |
|---|---|---|---|---|---|---|
| 1 | **Critical** | Missing popup warnings | [`dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | 271 | EditorLayout logout calls `manualLogout()` directly — no confirmation dialog. User may accidentally log out without warning about unsaved work. | Wrap in `showDialog` with "Are you sure you want to sign out?" confirmation, mirroring [`AdminDashboardScreen`](lib/features/admin/screens/admin_dashboard_screen.dart:588). |
| 2 | **Critical** | Missing popup warnings | [`dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | 1227 | ReaderLayout logout same issue — no confirmation dialog before `manualLogout()`. | Same fix as above. |
| 3 | **Critical** | Missing popup warnings | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 714–716 | Account card "Sign Out" button calls `manualLogout()` directly without confirmation. | Add confirmation dialog before signing out. |
| 4 | **Critical** | Missing popup warnings | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 1134–1138 | "Secure Logout" in About card calls `manualLogout()` directly without confirmation. | Add confirmation dialog before signing out. |
| 5 | **High** | Hardcoded values | [`dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | 535, 742–743, 1347 | `const Color(0xFF008751)` used directly for "synced" green status dot instead of theme `cs.primary` or a semantic token. Fails in dark mode where this specific green may have poor contrast. | Reference `cs.primary` or a semantically mapped color. If a specific green is desired, add it to [`AppTheme`](lib/core/theme/app_theme.dart) as a static const and document which contexts use it. |
| 6 | **High** | Hardcoded values | [`dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | 1349–1352 | ReaderLayout sync indicator uses hardcoded `Color(0xFF2196F3)`, `Color(0xFFBA1A1A)`, `Color(0xFF9E9E9E)` for syncing/error/offline states instead of theme `cs.primary`, `cs.error`, `cs.onSurfaceVariant`. | Reference theme `ColorScheme` tokens: `cs.primary`, `cs.error`, `cs.onSurfaceVariant`. |
| 7 | **High** | Hardcoded values | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 1279–1286 | `_syncStatusColor()` returns `Colors.grey`, `Colors.blue`, `Colors.green`, `Colors.red` — completely bypassing the Material theming system. These fail in dark mode and disregard user-selected accent colors. | Use semantic theme tokens: `cs.onSurfaceVariant` for offline, `cs.primary` for syncing, `cs.primary` for synced, `cs.error` for error. |
| 7b | **High** | Dark mode | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 866 | `Colors.green` used for online status icon color — not theme-aware. | Replace with `cs.primary` or a semantic success token. |
| 8 | **High** | Hardcoded values | [`conflict_resolution_screen.dart`](lib/features/settings/screens/conflict_resolution_screen.dart) | 200, 206 | `Colors.green.withValues(alpha: 0.10)` and `Colors.green` for empty-state success icon. Completely opaque to theme, invisible in some dark themes. | Use `cs.primary.withValues(alpha: 0.10)` for background and `cs.primary` for icon. |
| 9 | **High** | Hardcoded values | [`credit_counter.dart`](lib/core/widgets/credit_counter.dart) | 97, 101 | `Color(0xFF3674B5)` and `Colors.white` hardcoded for the credit dialog title icon — bypasses theme, poor dark mode support. | Use `cs.primaryContainer` / `cs.onPrimaryContainer`. |
| 10 | **High** | Hardcoded values | [`payment_screen.dart`](lib/features/payment/screens/payment_screen.dart) | 185, 382, 392, 536, 600 | `Colors.green` for success icon; `Colors.black` with alpha for processing overlay; `Colors.white` for overlay text; `Colors.black` for shadow; `Colors.white` for radio dot. None adapt to dark mode. | Use `cs.primary` for success; `cs.scrim.withValues(alpha: 0.32)` for overlay; `cs.onScrim` for overlay text. |
| 11 | **High** | Hardcoded values | [`vault_browser_screen.dart`](lib/features/vault/screens/vault_browser_screen.dart) | 296–297 | `Color(0xFF008751)` for sync status dot in nav drawer. | Reference theme token. |
| 12 | **High** | Hardcoded values | [`admin_dashboard_screen.dart`](lib/features/admin/screens/admin_dashboard_screen.dart) | 110–113, 1183–1187, 1361–1381, 1782–1790 | `Colors.white`, `Color(0xFF008751)`, `Color(0xFF2196F3)`, `Color(0xFFB71C1C)`, `Color(0xFF3674B5)`, `Color(0xFF5068D9)` all hardcoded for status dots, avatar backgrounds, and text. | Map to theme tokens: `cs.primary` for green status, `cs.tertiary` for yellow, `cs.error` for red, `cs.onSurfaceVariant` for gray. |
| 13 | **High** | Hardcoded values | [`teacher_detail_screen.dart`](lib/features/admin/screens/teacher_detail_screen.dart) | 273, 354, 361, 581 | `Colors.grey`, `Colors.green` used directly. | Replace with theme tokens. |
| 14 | **High** | Hardcoded values | [`admin_dashboard_screen.dart`](lib/features/admin/screens/admin_dashboard_screen.dart) | 1348–1357 | Sync status indicator icons/text use hardcoded colors in admin tab. | Reference `cs.primary`, `cs.error`, `cs.onSurfaceVariant`. |
| 15 | **Medium** | Static placeholder | [`dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | 976, 1020 | Dashboard stats "12" lessons created and "4" exams generated are **hardcoded** numbers, not from any provider or DB query. | Read actual counts from `lessonsDao.count()` and `examsDao.count()` via a `FutureProvider` or similar. |
| 16 | **Medium** | Static placeholder | [`dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | 722–777 | Sample lesson cards ("Introduction to Photosynthesis", "Algebraic Expressions") with fake statuses and timestamps — completely static data, not from DB. | Replace with a widget that reads from a `recentLessonsProvider` or similar, showing loading/empty states. |
| 17 | **Medium** | Static placeholder | [`dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | 1055–1072 | "Upcoming Schedule" displays hardcoded "10:00 AM · JSS 2 Biology Class" and "11:30 AM · SS 1 Math Exam" — no real schedule data. | Integrate with a timetable/schedule table or remove section if not yet implemented. |
| 18 | **Medium** | Static placeholder | [`vault_browser_screen.dart`](lib/features/vault/screens/vault_browser_screen.dart) | 270–275, 414 | "EP" hardcoded as user initials in nav drawer footer and mobile header — ignores actual user name from `authProvider`. | Read initials from `authData.currentTeacher.teacherName` using `_getInitials()` helper. |
| 19 | **Medium** | Static placeholder | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 259 | "Educator Profile" static label in sidebar — not reflective of actual user role/name. | Use `authData.currentTeacher?.teacherName ?? 'Educator'`. |
| 20 | **Medium** | Static placeholder | [`admin_dashboard_screen.dart`](lib/features/admin/screens/admin_dashboard_screen.dart) | 1651–1658 | Sync Health tab shows placeholder: "Sync health data will appear here after your first sync." — no implementation. | Either remove tab or implement with actual sync metrics from `syncStatusProvider`. |
| 21 | **Medium** | Incomplete feature | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 500–527 | Interface Mode radio buttons are completely non-functional: all use `groupValue: 'auto'` and `onChanged: (_) {}` — no state persistence or actual mode switching. | Connect to a `layoutModeProvider` (or similar) that persists user preference. |
| 22 | **Medium** | Incomplete feature | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 808–810 | "Purchase Credits" button shows toast "Purchase Credits — coming soon" — unlinked to payment flow. | Navigate to `/payment` route (already exists). |
| 23 | **Medium** | Incomplete feature | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 1051–1054 | "Privacy Policy" shows toast "coming soon". | Implement the screen or link. |
| 24 | **Medium** | Incomplete feature | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 1096–1099 | "About ClassAI" shows toast "coming soon". | Implement the screen or link. |
| 25 | **Medium** | Incomplete feature | [`dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | 1629 | "View Lesson" `FilledButton` has `onPressed: () {}` (no-op) — button is decorative, not functional. | Navigate to lesson editor with the lesson ID. |
| 26 | **Medium** | Incomplete feature | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 1231 | Settings bottom nav items have `onPressed: () {}` — do nothing. | Wire to actual routes (`/`, `/lessons`, `/exams`). |
| 27 | **Medium** | Incomplete feature | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 276–314 | Settings sidebar nav items (Home, Lessons, Exams, Vault, Admin) have no `onTap` handlers — non-functional. | Wire to actual routes. |
| 28 | **Low** | Reactive data | [`dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | 703 | "View All" button on recent lessons section — not wired to any navigation. | Navigate to `/lessons`. |
| 29 | **Low** | Reactive data | [`vault_browser_screen.dart`](lib/features/vault/screens/vault_browser_screen.dart) | 823, 836, 849 | Filter options (subject, class, curriculum) are hardcoded lists rather than dynamically loaded from the database. | Query distinct values from `vaultItemsDao` for dynamic filter options. |
| 30 | **Low** | Reactive data | [`exam_editor_screen.dart`](lib/features/exam/screens/exam_editor_screen.dart) | 54–79 | Subject/class dropdown lists are hardcoded arrays — should come from school configuration DB. | Load from `subjectsDao` or school config table. |
| 31 | **Low** | Reactive data | [`lesson_editor_screen.dart`](lib/features/lesson/screens/lesson_editor_screen.dart) | 64–91 | Same hardcoded subject/class dropdown lists as exam editor. | Load from DB. |
| 32 | **Low** | Reactive data | [`dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | 522–544 | `_SyncChip` defines its own mapping of `SyncStatus` to colors/labels — duplicates logic already in [`sync_indicator.dart`](lib/core/widgets/sync_indicator.dart:19-24). | Reuse the common mapping from `SyncIndicator` or a shared helper. |
| 33 | **Low** | Reactive data | [`credit_counter.dart`](lib/core/widgets/credit_counter.dart) | 47–48 | Credit counter shows "…" while loading but has no error state — if provider fails silently, user sees indefinite "…". | Add error handling; show error icon or "—" on failure. |
| 34 | **Low** | Empty/error state | [`dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | 1461+ | ReaderLayout recent lessons list uses `recentLessonsProvider` but has no empty state for when no lessons exist (e.g., new account). | Add empty state widget similar to [`lessons_list_screen.dart`](lib/features/lesson/screens/lessons_list_screen.dart:125-164). |
| 35 | **Low** | Empty/error state | [`dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | 1035–1073 | Schedule section has no loading, empty, or error state — it's 100% static placeholder data. | Remove or conditionally render based on real data availability. |
| 36 | **Low** | Dark mode | [`admin_dashboard_screen.dart`](lib/features/admin/screens/admin_dashboard_screen.dart) | 1348, 1362, 1373 | Admin Vault tab uses `Theme.of(context).colorScheme` for some colors but has hardcoded fallbacks. | Audit all color usage in admin screens and ensure they derive from `ColorScheme`. |
| 37 | **Low** | Layout/overflow | [`payment_screen.dart`](lib/features/payment/screens/payment_screen.dart) | 380–400 | Processing overlay uses `ColoredBox` with `Colors.black` — may cause layout overflow on very small screens. The overlay text uses `Colors.white` regardless of theme. | Use `Scaffold`-level overlay or `Stack` with positioned fills. Use `cs.scrim` and `cs.onScrim`. |
| 38 | **Low** | Layout/overflow | [`signup_screen.dart`](lib/features/auth/screens/signup_screen.dart) | 168 | Signup form constrained to `maxWidth: 400` — good practice, but review whether all form elements fit without overflow on small screens (360px width). | Add horizontal scroll or responsive padding breakpoints. |
| 39 | **Low** | Static placeholder | [`sms_otp_screen.dart`](lib/features/auth/screens/sms_otp_screen.dart) | 92, 103 | "SMS OTP is currently unavailable." and "Please use email-based verification instead." — intentionally stubbed but appears as a dead-end to users. | Either remove route or add an auto-redirect to email verification. |
| 40 | **Low** | Hardcoded values | [`payment_screen.dart`](lib/features/payment/screens/payment_screen.dart) | 449 | Mobile header shows hardcoded "\u20A6500" price — should reflect selected plan price. | Display actual selected plan price from `_plans` definition. |
| 41 | **Low** | Hardcoded values | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 1034 | App version fallback hardcoded as `'1.0.0'` — should derive from package info or show "—" if unavailable. | Use `package_info_plus` or similar for real version. |
| 42 | **Low** | Reactive data | [`settings_screen.dart`](lib/features/settings/screens/settings_screen.dart) | 46 | `_appVersion` fallback string `'1.0.0'`. | Already captured in #41. |

---

## Summary

| Priority | Count | Description |
|----------|-------|-------------|
| **Critical** | 4 | Missing logout confirmation dialogs — users can accidentally lose unsaved work |
| **High** | 10 | Hardcoded colors bypassing theme system, breaking dark mode compatibility |
| **Medium** | 14 | Static placeholder data, incomplete features, and non-functional controls |
| **Low** | 14 | Minor reactive data gaps, missing empty states, overflow concerns, and code duplication |
| **Total** | **42** | |

### Key Themes

1. **Dark Mode / Theming (10 High, 1 Low):** The app has a well-defined [`AppTheme`](lib/core/theme/app_theme.dart) with both light and dark color schemes, but many screens bypass it with hardcoded `Color()` and `Colors.*` constants. The worst offenders are the dashboard sync indicators, settings sync colors, conflict resolution empty state, credit dialog, payment screen overlay, and admin dashboard status indicators.

2. **Static Placeholder Data (5 Medium, 2 Low):** The dashboard bento grid is the most significant area with fake sample data — hardcoded lesson cards, stats (12 lessons, 4 exams), and schedule items. This creates a misleading first impression and provides no real value.

3. **Missing Logout Confirmation (4 Critical):** The admin dashboard correctly implements logout confirmation, but neither the EditorLayout, ReaderLayout, nor Settings screen do. Users can accidentally trigger logout, losing any unsaved lesson/exam editor state.

4. **Incomplete Features (6 Medium):** Interface Mode is entirely non-functional (radio buttons with no-op callbacks). Multiple features show "coming soon" toasts (Purchase Credits, Privacy Policy, About ClassAI). The Sync Health admin tab is a placeholder.

5. **Good Patterns Worth Preserving:**
   - Loading skeletons on exam/lesson list screens
   - Error states with retry buttons on data-driven screens
   - Proper use of `cs.colorScheme` in login, signup, change password, exam list, lesson list, vault detail, and conflict resolution screens
   - Reactive connections for sync, credit, and conflict providers
   - Comprehensive auth state machine with proper error handling
   - Responsive Editor/Reader layout switching on dashboard
