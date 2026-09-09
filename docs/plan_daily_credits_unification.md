# Plan: Daily Credits Unification

> **STATUS: R1 + R2 IMPLEMENTED AND DEPLOYED (2026-09-09).**
> All four R2 blocks committed (3d35a33, 7bb597a, 6fb7213, e0c864c);
> migration `20260909000003` pushed (Postgres-dialect fix: 7d5bd31);
> `sync-credits` deployed. Remaining: manual QA, ship R2, soak.
> R3 (server-side hardening) is future scope.
> See the Follow-up section at the bottom for the empty-exam-shells reminder.
>
> Unifies offline credits, daily previews, and daily generations into a single
> "daily credits" pool. Adds server-time reliance for the daily reset boundary.
> Adds per-tier subject restrictions. Removes the manual unlock step. Adds
> server-side security hardening to prevent bypass attacks.

---

## Context

The current app has **three separate rate-limiting systems** that all serve the
same purpose — gating how much a teacher can consume per day:

| System | Counter column | Config key | Used by |
|--------|---------------|------------|---------|
| Offline credits | `offlineCredits` | Server hardcoded to 3 | Unlock step, vault acquire |
| Daily previews | `dailyPreviewCount` / `dailyPreviewDate` | `daily_preview_limits` | Post-generation preview increment |
| Daily generations | `dailyGenerations` / `dailyGenerationDate` | `daily_generation_limits` | AI generation gate |

A Basic teacher (1 credit/day, 10 previews, 5 generations) could generate a
lesson but not unlock it the same day. The three systems fight each other.

**Goal:** One pool. One counter. One limit per tier. Server-authoritative daily
reset with local fallback. Auto-unlock on generation. Server-side enforcement on
AI proxy calls to prevent bypass.

---

## Tier Limits

| Tier | Daily Credits | Subjects Allowed | Notes |
|------|--------------|-----------------|-------|
| Free | 3 | N/A (cannot generate) | Tier gate blocks ALL generation. 3 credits usable for vault acquire only. |
| Basic | 1 | Mathematics, English, Science, Social Studies | Core academic subjects only |
| Standard | 3 | All subjects (`*`) | Full subject access is the upgrade incentive |
| Elite | Unlimited (-1) | All subjects (`*`) | Everything unlocked |

**Known limitation (R2 only):** Mid-day tier upgrades don't refresh credits
until next sync. R3 fixes this via server-side calculation.

---

## Subject Restrictions

### SQL seed

```json
{
  "basic": ["Mathematics", "English", "Science", "Social Studies"],
  "standard": ["*"],
  "elite": ["*"]
}
```

Free is omitted — the tier gate blocks generation before subjects are checked.
Subject name must be `"Science"` (not `"Basic Science"`) to match the hardcoded
`_subjects` list in both editors.

---

## Release 1: Rename & Fix

**Risk: 2/10** — No logic changes. Pure renaming, bug fixes, and label updates.

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 1.1 | Rename `OfflineCreditChip` → `DailyCreditsChip` | `dashboard_screen.dart` | 1/10 |
| 1.2 | Rename `OfflineCreditCounter` → `DailyCreditsCounter` | `lessons_list_screen.dart`, `exams_list_screen.dart`, `vault_browser_screen.dart` | 1/10 |
| 1.3 | Rename `OfflineCreditStateData` → `DailyCreditStateData` AND its `currentOfflineCredits` field → `currentDailyCredits` (consumers read the field directly, e.g. `exam_editor_screen.dart:672`) | `credit_state_provider.dart` + all consumers | 2/10 |
| 1.4 | Rename `OfflineCreditService` → `DailyCreditService` | `credit_service.dart` + callers | 2/10 |
| 1.5 | Update UI labels: "offline credits" → "daily credits" | `vault_item_detail_screen.dart`, `lesson_editor_screen.dart`, `exam_editor_screen.dart` | 1/10 |
| 1.6 | Fix `_tierFromCredits()` — derive tier from `subscriptionTier`, not credit count | `credit_state_provider.dart` | 2/10 |
| 1.7 | Add `subscription_tier` field to `sync-credits` response (keep existing fields for backward compat) | `supabase/functions/sync-credits/index.ts` | 3/10 |
| 1.8 | Rename payment screen label "Daily previews" → "Daily credits" (keep reading from `daily_preview_limits` — values change in R2) | `payment_screen.dart` | 1/10 |
| 1.9 | Remove `free` entry from `topic_restrictions_by_tier` SQL seed | SQL migration | 1/10 |
| 1.10 | Update dashboard credit info dialog text | `dashboard_screen.dart` | 2/10 |
| 1.11 | Update 6 test files for renamed classes: `lesson_editor_test.dart`, `credit_counter_test.dart`, `credit_service_test.dart`, `auth_state_machine_test.dart`, `reader_layout_test.dart`, `subject_gate_widget_test.dart` (its `_TestOfflineCreditNotifier` extends the renamed notifier) | test files | 1/10 |

---

## Release 2: Unify & Remove Unlock

**Risk: 5/10** — Structural changes. Ships after Release 1 is stable.

### Phase 2A — SQL Migration & Schema

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 2A.1 | Add `daily_credits_date TEXT` column to `security_config` | SQL migration, `security_config.dart` (Drift table) | 2/10 |
| 2A.2 | Seed `daily_credits_limit` key: `{"free":3,"basic":1,"standard":3,"elite":-1}` | SQL migration | 1/10 |
| 2A.3 | Seed `topic_restrictions_by_tier` key with correct per-tier subjects | SQL migration | 1/10 |
| 2A.4 | Remove `dailyGenerations`, `dailyGenerationDate`, `dailyPreviewCount`, `dailyPreviewDate` from Drift definition (columns stay in SQLite, unused) | `security_config.dart` table | 5/10 |
| 2A.5 | Remove `daily_preview_limits` and `daily_generation_limits` keys from `app_config` | SQL migration | 3/10 |
| 2A.6a | **Data migration (lessons):** `UPDATE lessons SET is_unlocked = 1 WHERE status IN ('generated', 'completed') AND is_unlocked = 0` | SQL migration | 4/10 |
| 2A.6b | **Data migration (exams):** the exams table has NO `status` column — inspect content instead: `UPDATE exams SET is_unlocked = 1 WHERE is_unlocked = 0 AND (json_array_length(json_extract(content, '$.mcqs')) > 0 OR json_array_length(json_extract(content, '$.theory')) > 0 OR json_array_length(json_extract(content, '$.subjective')) > 0)`. Test in a scratch DB first. Rows whose content is not valid JSON (legacy encrypted rows) stay locked — audit them manually after migration. | SQL migration | 5/10 |

**2A.6 rationale:** Lessons uses `status IN ('generated', 'completed')` (not
`content != '{}'`) to avoid incorrectly unlocking draft lessons that have
manually edited content. Exams have no status column, so 2A.6b checks whether
the content JSON actually contains questions. The editor's load path
(`_isUnlocked = lesson.status == 'draft' || (lesson.isUnlocked && _hasGenerated)`)
means a completed lesson with `isUnlocked = false` would load locked with no
unlock button left — hence 'completed' must be included.

### Phase 2B — Core Logic

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 2B.1 | Add `dailyCreditsLimit` getter to `ConfigService` | `config_service.dart` | 1/10 |
| 2B.2 | Add `_dailyCreditLimit(tier)` to `SecurityConfigDao` | `security_config_dao.dart` | 2/10 |
| 2B.3 | Add `checkAndSpendDailyCredits({required String tier, int cost = 1})` — always spends. Returns `true` if allowed, `false` if limit exceeded. Handles date reset, tier limit, spend. | `security_config_dao.dart` | 5/10 |
| 2B.4 | Add `getRemainingDailyCredits({required String tier})` — read-only, does NOT spend. Separate from 2B.3. | `security_config_dao.dart` | 2/10 |
| 2B.5 | Update `AiService.checkDailyLimit()` → call `checkAndSpendDailyCredits()` | `ai_service.dart` | 5/10 |
| 2B.6 | Update `DailyCreditService` vault spend → call `checkAndSpendDailyCredits()` (boolean return). Update the vault UI catch sites that currently catch `OfflineCreditInsufficientException` — they must handle the `false` return and show their own insufficient-credit message, since `InsufficientOfflineCreditScreen` is deleted in 2G.1. | `credit_service.dart`, vault UI screens | 5/10 |
| 2B.7 | Remove `checkAndIncrementDailyGenerations()`, `checkAndIncrementDailyPreviews()`, `_previewLimit()`, `_generationLimit()` | `security_config_dao.dart` | 4/10 |
| 2B.8 | Remove `getRemainingDailyGenerations()`, `getDailyGenerationLimit()` | `security_config_dao.dart` | 3/10 |

**2B.3 vs 2B.4 design:** `checkAndSpendDailyCredits()` ALWAYS spends (no
`increment` parameter). `getRemainingDailyCredits()` is a pure read. No
circular dependency. Display widgets call 2B.4. Generation/vault calls 2B.3.

**Known limitation (R2 only):** Credits lost on failed AI generation (same as
current behavior). R3 fixes this server-side with insert-before/refund-on-failure.

### Phase 2C — Server-Time Integration

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 2C.1 | Update `sync-credits/index.ts` — return `{ daily_credits_date: "YYYY-MM-DD", tier: "standard" }` (NO `daily_credits` value in R2 — server doesn't know local spend). Client uses date for reset detection only. | `supabase/functions/sync-credits/index.ts` | 4/10 |
| 2C.2 | Update `_syncCreditState()` — call `server-time`, compare against `dailyCreditsDate`, reset if new server day, overwrite local date with server date | `sync_service.dart` | 5/10 |
| 2C.3 | `checkAndSpendDailyCredits()` uses `DateTime.now()` for offline date check | `security_config_dao.dart` | 2/10 |
| 2C.4 | Store last server time from `_syncCreditState()` in `dailyCreditsDate` column | `security_config_dao.dart` | 2/10 |

**2C.1 note:** In R2, the server only provides the authoritative DATE. The
client manages the counter locally. R3 adds the `daily_credits` value when the
spend table exists.

**Deployment order:** Server (2C.1) must deploy BEFORE client (2C.2-2C.4).

### Phase 2D — Auth & Sync Cleanup

| # | Change | File(s) | Risk | Commit grouping |
|---|--------|---------|------|----------------|
| 2D.1 | Remove `offlineCredits` from `AuthResult` | `auth_service.dart` | 4/10 | **Same commit as 2D.2** |
| 2D.2 | Remove `offlineCredits` from auth state data class | `auth_provider.dart` | 4/10 | **Same commit as 2D.1** |
| 2D.3 | Replace old `_syncCreditState()` with server-time version | `sync_service.dart` | 4/10 | — |
| 2D.4 | Remove `lastCreditRefillServerTime` references from DAO | `security_config_dao.dart` | 2/10 | — |

### Phase 2E — Editor UI (Unlock Removal)

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 2E.1 | Remove `_handleUnlock()` from lesson editor | `lesson_editor_screen.dart` | **7/10** |
| 2E.2 | In lesson editor `_handleGenerate()` success path, change `_isUnlocked = false;` → `_isUnlocked = true;` — the assignment inside the post-frame `setState` block that populates the generated sections, immediately before `_saveLesson(notify: false)` (context-anchored, not line-anchored) | `lesson_editor_screen.dart` | **7/10** |
| 2E.3 | Remove unlock button, unlock bottom sheet, "Out of offline credits" toast from lesson editor | `lesson_editor_screen.dart` | 5/10 |
| 2E.4 | Remove `_handleUnlock()` from exam editor | `exam_editor_screen.dart` | **7/10** |
| 2E.5 | Change `_isUnlocked = false;` → `_isUnlocked = true;` in exam editor `_handleGenerate()` success path (inside the `setState` before `_saveExam()`) | `exam_editor_screen.dart` | **7/10** |
| 2E.6 | Remove unlock button, unlock bottom sheet from exam editor | `exam_editor_screen.dart` | 5/10 |
| 2E.7 | Remove `_offlineCreditBalance`, `_remainingDailyPreviews`, `_loadOfflineCreditBalance()`, `_loadDailyPreviewData()` from both editors | `lesson_editor_screen.dart`, `exam_editor_screen.dart` | 4/10 |
| 2E.8 | Add `_loadDailyCredits()` to both editors — calls `getRemainingDailyCredits(tier:)`, sets `_dailyCredits` state. Called from `_checkConnectivity()` post-frame callback. | both editors | 3/10 |
| 2E.9 | Remove the `onUnlock` parameter and its widget wiring — lesson editor: widget field (~4624), constructor (~4723), getter (~5188), button onPressed (~5274), call site (~3033); exam editor: field (~2778), constructor (~2799), button onPressed (~2950), call sites (~1741, ~1845). Deleting `_handleUnlock()` without removing these → compile errors. | both editors | 5/10 |
| 2E.10 | Remove post-generation `checkAndIncrementDailyPreviews()` calls — lesson editor has TWO (test-callback path ~1310 and production path ~1343), exam editor has ONE (~896). Do NOT replace them with spend calls — `checkDailyLimit()` already spent the credit pre-generation; replacing would double-spend. | both editors | 5/10 |
| 2E.11 | Add `ref.invalidate(lessonsListProvider)` / `ref.invalidate(examsListProvider)` to the generation success path — the old unlock flow invalidated these; without it the list screen shows stale "Draft" status after auto-unlock generation. | both editors | 3/10 |
| 2E.12 | Grep for other callers of `_showSyncBottomSheet()` — if `_handleUnlock()` was its only caller, delete the orphaned method. | both editors | 2/10 |

**Highest risk in entire plan.** 2E.1-2E.12 change a core user flow. If
`isUnlocked = true` is not set on generation success, generated content stays
locked forever. Requires manual QA of: generate → view → navigate away → return
→ verify editable.

### Phase 2F — Lists, Dashboard, Payment

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 2F.1 | Remove "Unlocked" from `_statusFilters` in lessons_list and exams_list | `lessons_list_screen.dart`, `exams_list_screen.dart` | 3/10 |
| 2F.2 | Update `DailyCreditStateData.refresh()` → use `getRemainingDailyCredits()` | `credit_state_provider.dart` | 4/10 |
| 2F.3 | Update `payment_screen.dart` — read from `dailyCreditsLimit` | `payment_screen.dart` | 2/10 |
| 2F.4 | Update dashboard credit info dialog | `dashboard_screen.dart` | 3/10 |

### Phase 2G — Cleanup

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 2G.1 | Delete `insufficient_credit_screen.dart` | file deletion | 3/10 |
| 2G.2 | Remove `/insufficient-offline-credit` route AND update `credit_counter.dart` (~line 127) which pushes it — rewire the chip tap to open the credit info dialog instead. Removing the route without updating the tap handler → runtime "route not found" error. | `app_router.dart`, `credit_counter.dart` | 4/10 |
| 2G.3 | Remove `SubscriptionTierX.offlineCredits` extension | `curriculum_types.dart` | 3/10 |
| 2G.4 | Grep audit for any remaining `offlineCredit` references | all Dart files | 2/10 |
| 2G.5 | Remove `OfflineCreditInsufficientException` class (orphaned after 2B.6 rewires vault spend to a boolean return) | `credit_service.dart` | 2/10 |

### Phase 2H — Tests

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 2H.1 | Unit test for `checkAndSpendDailyCredits()` — reset, limit, cost | new test | 1/10 |
| 2H.2 | Unit test for `getRemainingDailyCredits()` — read-only, no spend | new test | 1/10 |
| 2H.3 | Widget test for auto-unlock — generation sets `isUnlocked = true` | new test | 1/10 |
| 2H.4 | Update `lesson_editor_test.dart` | test file | 2/10 |
| 2H.5 | Update `credit_counter_test.dart` | test file | 2/10 |
| 2H.6 | Update `credit_service_test.dart` | test file | 2/10 |
| 2H.7 | Update `auth_state_machine_test.dart` | test file | 1/10 |
| 2H.8 | Update `reader_layout_test.dart` | test file | 1/10 |

---

## Release 3: Security Hardening

**Risk: 4/10** — Server-side enforcement. Ships after Release 2 is stable.

### Phase 3A — Server-Side Daily Credits Table

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 3A.1 | Create `daily_credits` table: `teacher_id UUID`, `date TEXT`, `total_cost INT DEFAULT 0`, `created_at TIMESTAMPTZ`. Unique constraint on `(teacher_id, date)`. | SQL migration | 3/10 |
| 3A.2 | Update `sync-credits/index.ts` — query `daily_credits.total_cost` for teacher's today spend. Calculate `remaining = tier_limit - total_cost`. Return `{ daily_credits: N, daily_credits_date, tier }`. | `supabase/functions/sync-credits/index.ts` | 5/10 |
| 3A.3 | Update `_syncCreditState()` — apply server's authoritative credit count to local DB | `sync_service.dart` | 3/10 |

**3A.1 note:** Column is `total_cost` (not `cost`) to clarify it represents the
total credits spent that day, not per-event cost. Single row per teacher per
day. On each spend: `UPDATE daily_credits SET total_cost = total_cost + $cost
WHERE teacher_id = $1 AND date = $2`. If no row exists: `INSERT`.

### Phase 3B — Server-Side AI Proxy Validation

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 3B.1 | AI proxy validates subscription — query `schools.expiry_date` + `subscription_tier` using server time. If expired or free, reject 403. | `deepseek-proxy/index.ts`, `gemini-proxy/index.ts` | 5/10 |
| 3B.2 | AI proxy validates daily credits — query `daily_credits.total_cost` for today. If `total_cost >= tier_limit`, reject 429. | both proxy files | 5/10 |
| 3B.3 | AI proxy increments BEFORE AI call — `INSERT ... ON CONFLICT SET total_cost = total_cost + $cost`. Prevents double-spend race condition. | both proxy files | 4/10 |
| 3B.4 | AI proxy refunds on failure — if AI returns non-200 or unparseable response, `UPDATE daily_credits SET total_cost = total_cost - $cost`. | both proxy files | 3/10 |

**3B.1-3B.4 execution order:**
```
1. Validate JWT (existing)
2. Query schools → reject if expired/free (3B.1)
3. INSERT/UPDATE daily_credits (+cost) (3B.3)
4. Call DeepSeek/Gemini
5. If failed → UPDATE daily_credits (-cost) (3B.4)
6. Return response
```

### Phase 3C — Subscription Expiry Hardening

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 3C.1 | Periodic server-time check — 15-minute timer. If unavailable 3 consecutive times, force tier to free. | `auth_provider.dart` | 3/10 |
| 3C.2 | Server-time unavailable fallback — force free tier until successful check. | `auth_provider.dart` | 3/10 |
| 3C.3 | Add `subscription_tier` + `expiry_date` to JWT claims at login/activate. Proxy validates against DB (DB is source of truth, JWT is hint). | `login/index.ts`, `activate/index.ts` | 3/10 |

### Phase 3D — Tamper Detection

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 3D.1 | HMAC on credit state — server signs response, client stores signature, server validates on next sync. | `sync-credits/index.ts`, `security_config_dao.dart` | 4/10 |
| 3D.2 | Clock-jump detection — if date jumps >1 day forward or backward, require server-time check before generation. | `security_config_dao.dart` | 3/10 |
| 3D.3 | Supabase RLS on `daily_credits` — teachers read own rows only, edge functions write via service role. | SQL migration | 2/10 |

### Phase 3E — Rate Limiting

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 3E.1 | AI proxy rate limit — 10 req/min per teacher via Deno KV. | proxy files | 3/10 |
| 3E.2 | sync-credits rate limit — 5 req/min per teacher. | `sync-credits/index.ts` | 2/10 |

### Phase 3F — Tests

| # | Change | File(s) | Risk |
|---|--------|---------|------|
| 3F.1 | Integration test — expired subscription returns 403 | new test | 1/10 |
| 3F.2 | Integration test — exceeded credits returns 429 | new test | 1/10 |
| 3F.3 | Integration test — failed generation refunds credit | new test | 1/10 |
| 3F.4 | Unit test — HMAC tamper detected | new test | 1/10 |
| 3F.5 | Unit test — clock-jump flagged | new test | 1/10 |
| 3F.6 | Unit test — tier forced to free after 3 failed server-time checks | new test | 1/10 |

---

## What Does NOT Change

- `lessons.isUnlocked` / `exams.isUnlocked` DB fields — stay, auto-set on generate
- Vault publisher `offlineCreditCost` — renamed in future release
- Sync queue, merge engine, auth login flow
- `server-time` edge function — already exists

---

## Dependency Order

```
Release 1 → stable in prod
  → Release 2A (schema + data migration)
    → Release 2B (core logic) ← same commit as 2A.5
      → Release 2C (server-time) ← server deploy first
        → Release 2D (auth cleanup) ← 2D.1+2D.2 same commit
          → Release 2E (unlock removal) ← manual QA required
            → Release 2F (UI)
              → Release 2G (cleanup)
                → Release 2H (tests) → stable in prod
                  → Release 3A (daily_credits table)
                    → Release 3B (AI proxy validation)
                      → Release 3C (expiry hardening)
                        → Release 3D (tamper detection)
                          → Release 3E (rate limiting)
                            → Release 3F (tests)
```

---

## Execution Strategy

> **Hidden trap:** the linear order deletes old DAO methods (2B.7/2B.8) before
> the editors' call sites are removed (2E.7/2E.10) → compile errors.
> **Fix: add first, delete last.** Nothing is deleted until its last caller is
> gone (confirmed by the 2G.4 grep audit).

| Block | Phases | Pause after | Gate |
|-------|--------|-------------|------|
| 0 | Release 1 (1.1–1.11) | PAUSE 1 | full `flutter test` + smoke — behavior identical, ship/soak |
| 1 | 2A.1–2A.3, 2B.1–2B.6, 2H.1–2H.2 pulled forward (additive only; SKIP 2A.4, 2A.5, 2B.7, 2B.8) | PAUSE 2 | tests green; old+new coexist; app fully working |
| 2 | 2C (deploy 2C.1 server FIRST), 2D (2D.1+2D.2 same commit) | PAUSE 3 | verify server date applied; manual day-rollover test |
| 3 | 2E (unlock removal, all of 2E.1–2E.12 in one pass) | PAUSE 4 (HARD) | manual QA: generate → view → navigate away → return → editable, for lessons AND exams |
| 4 | Now delete 2B.7, 2B.8, 2A.4, 2A.5; then 2F, 2G (do NOT skip 2G.2 tap rewire), 2H.3–2H.8, grep audit | PAUSE 5 | full suite; ship R2, soak in prod |
| 5 | 3A + 3B (server deploys first) | PAUSE 6 | verify 403/429/refund against real proxy calls |
| 6 | 3C, 3D, 3E, 3F (independent; can land incrementally) | — | hardening complete |

**SQL Migration Application**

Each SQL migration file in `supabase/migrations/` must be applied to the remote
Supabase database before its corresponding client code ships. Apply via:

```bash
supabase db push
```

Or manually via the Supabase Dashboard SQL Editor. The migration files use
`INSERT ... ON CONFLICT ... DO UPDATE` (upsert), so re-applying is safe.

| Migration file | Applied when |
|---------------|-------------|
| `20260906_000001_seed_generation_limits_and_topic_restrictions.sql` | Before R1 client ships |
| `20260908_000002_seed_daily_credits_limit.sql` | Before Block 2 client ships |

**Two rules regardless of block:**
1. Server always deploys before the client that consumes it (2C.1, then 3A/3B).
2. Never end a session mid-phase — every pause lands on a compiling, fully-tested app.

---

## Audit: All Logic Inconsistencies Found & Fixed

| # | Issue | Severity | Fix |
|---|-------|----------|-----|
| L1 | "Basic Science" doesn't match editor's "Science" | HIGH | Changed to "Science" |
| L2 | R1.8 payment screen shows wrong values during transition | HIGH | R1 renames label only, R2 switches getter |
| L3 | 2A.5 removes old key before new getter exists | HIGH | 2A.5 + 2B.1 same commit |
| L4 | 2C.1 queries spend but table doesn't exist until R3 | HIGH | 2C.1 returns date+tier only, no spend value |
| L5 | H3 inserts after success, H9 deletes on failure — contradictory | MEDIUM | 3B.3 inserts BEFORE, 3B.4 refunds on failure |
| L6 | Pre-R2 items with content but isUnlocked=false appear as Draft | MEDIUM | 2A.6 uses `status = 'generated'` (not content check) |
| L7 | Removed loading method has no replacement | LOW | 2E.8 adds `_loadDailyCredits()` |
| L8 | 2D.1 removes offlineCredits without listing callers | MEDIUM | Added grep audit requirement |
| L9 | Free tier 3 credits only usable for vault | INFO | Documented as intentional |
| L10 | JWT tier claim stale after mid-session expiry | LOW | 3B.1 queries DB directly |
| L11 | 2A.6 migration too broad — unlocks draft lessons with content | HIGH | Changed to `WHERE status = 'generated'` |
| L12 | `increment` param on checkAndSpendDailyCredits unnecessary | MEDIUM | Removed param, split into spend (2B.3) vs read (2B.4) |
| L13 | 2C.1 returns daily_credits value but server doesn't know spend in R2 | HIGH | Removed daily_credits from R2 response, added in R3 |
| L14 | 2D.1 and 2D.2 must be same commit | MEDIUM | Added commit grouping column |
| L15 | 2E.2/2E.5 don't specify exact code location | MEDIUM | Specified exact line: `_isUnlocked = false` → `true` |
| L16 | 3A.1 `cost` column ambiguous in single-row design | LOW | Renamed to `total_cost` |
| L17 | Mid-day tier upgrade doesn't refresh credits (R2) | LOW | Documented as known R2 limitation |
| L18 | R2 loses credits on failed generation | LOW | Documented, R3 fixes server-side |
| L19 | 2A.6 assumed exams have a `status` column — they don't (only `isUnlocked`); the migration SQL would error with "no such column" | HIGH | Split into 2A.6a (lessons, status-based) and 2A.6b (exams, json_extract content check with encrypted-row caveat) |
| L20 | 2A.6 missed `status = 'completed'` lessons — a completed lesson with `isUnlocked = false` loads locked in the editor with no unlock button left | HIGH | Migration now covers `status IN ('generated', 'completed')` |
| L21 | `onUnlock` parameter threaded through ~9 widget sites in both editors — deleting `_handleUnlock()` alone → compile errors | HIGH | Added 2E.9 listing every wiring site |
| L22 | Post-generation `checkAndIncrementDailyPreviews()` calls (3 sites) not covered by 2B.7 removal → compile errors; blindly replacing them → double-spend | HIGH | Added 2E.10: delete the calls, never replace |
| L23 | Unlock flow invalidated `lessonsListProvider`/`examsListProvider`; the generation path doesn't → stale "Draft" status in list after auto-unlock | MEDIUM | Added 2E.11 invalidation to generation success path |
| L24 | `_showSyncBottomSheet()` may be orphaned when `_handleUnlock()` is removed | LOW | Added 2E.12 grep-and-delete step |
| L25 | `credit_counter.dart:127` pushes `/insufficient-offline-credit`; route removal without rewiring the tap → runtime error | HIGH | 2G.2 now includes the tap-handler rewire |
| L26 | `subject_gate_widget_test.dart` extends `OfflineCreditStateNotifier` but was missing from 1.11's test list | MEDIUM | 1.11 now lists all 6 files explicitly |
| L27 | `currentOfflineCredits` field rename not explicit in 1.3 | LOW | 1.3 now names the field |
| L28 | `OfflineCreditInsufficientException` orphaned after 2B.6; vault UI catch sites expect a thrown exception, not a boolean | MEDIUM | 2B.6 note + 2G.5 removal |
| L29 | 2E.2 referenced a fixed line number (1439) that shifts with any edit | LOW | Context-anchored description instead |

---

## Risk Summary

| Release | Phase | Risk |
|---------|-------|------|
| R1 | Rename & Fix | **2/10** |
| R2-A | Schema + Data Migration | 4/10 |
| R2-B | Core Logic | 5/10 |
| R2-C | Server-Time | 4/10 |
| R2-D | Auth Cleanup | 4/10 |
| R2-E | Unlock Removal | **7/10** |
| R2-F | Lists/Dashboard | 3/10 |
| R2-G | Cleanup | 3/10 |
| R2-H | Tests | 2/10 |
| R3-A | Daily Credits Table | 3/10 |
| R3-B | AI Proxy Validation | 5/10 |
| R3-C | Expiry Hardening | 3/10 |
| R3-D | Tamper Detection | 4/10 |
| R3-E | Rate Limiting | 3/10 |
| R3-F | Tests | 1/10 |
| **Overall** | | **4/10** |

---

## Follow-up (added 2026-09-09): Empty exam shells — REMINDER

**Reminder:** after R2 ships, revisit the **109 empty exam shells** found during
the post-migration audit of `20260909000003`.

**What they are:** server rows in `public.exams` with
`is_unlocked = false` and content exactly `{"mcqs":[],"theory":[],"subjective":[]}`.
Created 2026-07-25 → 2026-08-15 by a single teacher account; topic/week/term are
filled, questions are not. They are pre-fill scaffolds from the scheme-of-work
flow (and older manual drafts), not real exams — the current client
(`ExamGenerationService.generateCombinedExam`) either fills them or creates its
own. The unlock migration correctly skipped them (no content to unlock).

**Verdict: effectively useless, but they are the teacher's data.**

**Proposed cleanup plan (do NOT run before R2 ships and soaks):**

| Step | Action | Risk |
|------|--------|------|
| C.1 | Ship R2, soak ≥ 1 week, confirm no user complains about "missing" empty exams | — |
| C.2 | Confirm the client treats empty exams as draft (exams_list shows them under Draft; no crash on open) — if the list already hides/filters them, user impact of deletion is zero | 2/10 |
| C.3 | Migration `cleanup_empty_exam_shells.sql`: soft-delete only — `UPDATE exams SET deleted_at = now() WHERE is_unlocked = false AND content = '{"mcqs":[],"theory":[],"subjective":[]}'` (scoped, reversible). If the table has no `deleted_at` column, add it first, or fall back to a dated archive table (`exams_empty_shells_archive_YYYYMMDD`) instead of DELETE | 3/10 |
| C.4 | Client-side: extend the exams sync-pull handling to reconcile server-removed exams on next sync (delete local rows whose server_id is gone), so devices converge; the current pull only reconciles the teacher roster | 4/10 |
| C.5 | Optional: same audit for empty lesson shells (lessons with empty objectives/presentation but status 'draft') once C.4 lands | 2/10 |
| C.6 | After another soak period, hard-delete the archive | 1/10 |

**Do not** bulk-DELETE live rows without C.4 — local devices that still hold
those rows would re-insert them on their next sync push.
