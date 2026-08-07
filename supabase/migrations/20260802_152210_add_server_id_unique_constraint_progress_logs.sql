-- ============================================================================
-- Migration: Add UNIQUE constraint on progress_logs.server_id
-- Date: 2026-08-02 15:22:10 UTC
-- Description:
--   Stops duplicate rows from being created when the client pushes an INSERT
--   for a record that already exists on the server (stale queue entry from a
--   crash between _updateLocalServerId and removeQueueEntry).
--
--   Three-layer defence against this specific bug:
--     1. Client-side stale-INSERT detection (_pushChanges() in sync_service.dart)
--        checks if the local record already has a serverId before sending an
--        INSERT. If it does, it injects server_id into the payload and converts
--        the operation to UPDATE.
--     2. Server-side: sync-push Edge Function uses upsert().onConflict('server_id')
--        when the payload includes server_id.
--     3. UNIQUE partial index on (server_id) WHERE server_id IS NOT NULL.
--
--   Important: the UNIQUE index is general data integrity, not independent
--   protection against a stale INSERT that reaches the server with server_id
--   still NULL. That stale-INSERT case is handled by Layer 1.
--
--   Production check before this migration found 0 duplicate server_id groups
--   for progress_logs, so no dedup step is needed here.
--
--   SAFETY: Full table snapshot is taken BEFORE the constraint is added so the
--   table can be restored if needed:
--     SELECT * FROM progress_logs_backup_20260802_152210;
-- ============================================================================

-- 0. Snapshot table before adding the constraint
CREATE TABLE progress_logs_backup_20260802_152210 AS SELECT * FROM progress_logs;

-- 1. Add UNIQUE constraint on progress_logs.server_id
-- Partial index: only applies to non-null server_id values.
-- PostgreSQL treats NULLs as distinct, so multiple rows with server_id = NULL
-- are still allowed (fine for brand-new records that haven't synced yet).
--
-- NOTE: This does NOT protect against the stale-INSERT bug by itself (see
-- header comment for explanation). It is general data integrity: prevents
-- manual INSERTs or future code bugs that explicitly reuse a non-null server_id.
CREATE UNIQUE INDEX IF NOT EXISTS idx_progress_logs_server_id
  ON progress_logs (server_id)
  WHERE server_id IS NOT NULL;
