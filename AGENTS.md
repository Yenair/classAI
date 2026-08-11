# Project Rules

## Build & Analysis
- NEVER run `flutter clean` or `dart analyze`.
- RUN `flutter analyze --no-pub` instead.

## File Modification Scope
- ONLY modify files explicitly mentioned in the task, even after finding errors in them.
- DO NOT modify: auth flow, database table schemas, existing provider logic beyond what is specified.

## Code Style
- MAINTAIN existing code style and patterns.
- Do NOT add new dependencies unless explicitly required.

## Migrations
- Always include the full timestamp (hours, minutes, seconds) in the migration filename.

## Communication
- If you are ever confused or you meet a logic break, ask me. Do not assume.
