# ClassAI Agent Prompt (Compact)

You are building the ClassAI Flutter app phase by phase. I will give you the current phase file.

## Essential Rules (from prior debugging)

1. **Drift columns**: Never name a column `tableName` or `entityName`. Use `queueTable`, `targetTable`, etc.
2. **Companion inserts**: Wrap optional int/bool fields with `Value(...)` (e.g., `attempts: Value(attempts)`).
3. **DAOs**: Must be in separate files under `lib/core/database/daos/`. In `database.dart` add only getters like `XDao get xDao => XDao(this);`.
4. **Drift queries**: `select(table).getSingle()` for one row; `(update(table)..where(...)).write(...)`; `into(table).insert(Companion.insert(...))`.
5. **No method shadowing**: Rename custom `update` methods (e.g., `updateConfig`) to avoid conflicting with Drift's `update`.
6. **Tests**: Always use `AppDatabase.forTesting()` (in‑memory). Import with `package:classai/...`.
7. **local_auth**: Use named params: `await localAuth.authenticate(localizedReason: '...', stickyAuth: false, biometricOnly: true)`. Do **not** use `AuthenticationOptions`.
8. **Cryptography**: Argon2id (password→key), AES‑256‑GCM (content encryption), AES‑KWP (key wrapping) are all separate tools; never replace one with another.

## Supabase Backend (Already Designed)

- PostgreSQL with UUID PKs, soft delete, RLS. JWT claims: `teacher_id`, `school_id`, `is_admin`.
- Teachers can CRUD their school's data except DELETE on `subjects`/`scheme_of_work` (admin‑only).
- Internal tables (`sync_queue`, `version_hashes`, `conflicts`) are server‑only.
- **Frontend**: Use `dio` with **mock interceptors** for now (real Supabase calls come later). When building auth/sync services, follow the API contracts in the roadmap's Appendix B.

## Workflow

For each phase, follow the “Agent Playbook” order. For every file:

- Write the full code with correct imports.
- Show the file path as `// lib/core/...`.
- If modifying an existing file, provide the **complete new content** and note what changed.

After all files, output the CLI commands:

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
git add .
git commit -m "Phase X: description"
git push
```

