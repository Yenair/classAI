
```markdown
`phase_06_ui.md`
# Phase 6: UI — Producer Dashboard + Reader Mode (Self-Contained)

**Goal**: Complete Editor dashboard on desktop/large tablet. Reader mode on phone/small tablet. Platform-gated layout. NavigationRail vs BottomNav. Sync indicator, credit counter, conflict notification banner.

## Architecture Decisions (This Phase Only)

- **Platform gate**: `MediaQuery.of(context).size.shortestSide >= 600` → Editor. User override in `shared_preferences` key `platform_mode_override` (values: `editor`, `reader`, `auto`).
- **Editor layout**: NavigationRail (compact on ≤1024px, extended on >1024px) on left; `Expanded` content area on right. AppBar with sync indicator + credit counter.
- **Reader layout**: `BottomNavigationBar` 4 tabs (Home, Lessons, Exams, More). ≥16pt font. Compact card UI.
- **Sync indicator**: `IconButton` in AppBar. Gray cloud=offline, blue cloud_sync=syncing, green cloud_done=synced, red cloud_alert=error. Tap → `showModalBottomSheet` with sync details.
- **Credit counter**: `ActionChip` in AppBar. Shows "🔓 X". Tap → `AlertDialog` with tier, last refill, cooldown.
- **Conflict banner**: `MaterialBanner` below AppBar. Shows count. "REVIEW" button → conflict resolution screen.

## Agent Playbook — Phase 6 File Creation Order

### Step 6.1: `lib/core/utils/platform_helper.dart`
```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlatformHelper {
  static Future<bool> isEditorMode(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final override = prefs.getString('platform_mode_override');
    if (override == 'editor') return true;
    if (override == 'reader') return false;
    return MediaQuery.of(context).size.shortestSide >= 600;
  }
}
```

### Step 6.2: `lib/core/widgets/sync_indicator.dart`
`ConsumerWidget`. Reads `syncStatusProvider` (Riverpod). Renders appropriate icon + color. Tap → `SyncDetailsSheet` (modal bottom sheet with: last sync time, pending push count, pending pull count, conflict count, network status, manual "Sync Now" button if online and not syncing).

### Step 6.3: `lib/core/widgets/credit_counter.dart`
`ConsumerWidget`. Reads `creditStateProvider`. Renders `ActionChip`. Tap → `CreditDetailsDialog` (AlertDialog with: current credits, tier name, next refill time, "Upgrade" button → payment flow).

### Step 6.4: `lib/core/widgets/conflict_banner.dart`
`ConsumerWidget`. Reads `unresolvedConflictsProvider`. If count > 0: renders `MaterialBanner` with warning icon and "REVIEW" button. REVIEW navigates to `/conflicts`.

### Step 6.5: `lib/features/dashboard/screens/dashboard_screen.dart`
```dart
class DashboardScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<bool>(
      future: PlatformHelper.isEditorMode(context),
      builder: (_, snap) => (snap.data ?? false) ? const EditorLayout() : const ReaderLayout(),
    );
  }
}
```

`EditorLayout`: `Scaffold` → `Row` of `NavigationRail` (5 destinations) + `Expanded` content with `ConflictBanner`.
`ReaderLayout`: `Scaffold` → body with `ConflictBanner` + content + `BottomNavigationBar` (4 destinations).

### Step 6.6: `lib/features/settings/screens/conflict_resolution_screen.dart`
`ConsumerWidget`. Lists unresolved conflicts from `conflicts` table via Riverpod. Each conflict card shows: record type, field name, local value, remote value. Actions: "Keep Mine" (resolution=local), "Keep Theirs" (resolution=remote), "Merge" (resolution=merged, auto-union for arrays). On resolve: update conflict record, update underlying data record, refresh sync state.

### Step 6.7: `lib/router/app_router.dart`
GoRouter configuration with routes: `/` (dashboard), `/login`, `/lessons/:id`, `/exams/:id`, `/conflicts`, `/admin`, `/vault`, `/settings`, `/payment`. Deep link handling for `classai://reset-password?token=`, `classai://activate?code=`, `classai://admin-recovery?token=`.

## Phase 6 Acceptance Criteria (GATE)

```bash
flutter test test/ui/platform_gate_test.dart             # Editor/reader routing
flutter test test/ui/dashboard_layout_test.dart          # NavigationRail + ContentArea
flutter test test/ui/reader_layout_test.dart             # BottomNav + card layout
flutter test test/ui/sync_indicator_test.dart            # 4-sync-status rendering
flutter test test/ui/credit_counter_test.dart            # Chip + dialog
flutter test test/ui/conflict_banner_test.dart           # Banner shown/hidden, REVIEW navigates
flutter test test/ui/conflict_resolution_test.dart       # Keep mine/theirs/merge
flutter test test/router/deep_links_test.dart            # Deep link parsing
```
```