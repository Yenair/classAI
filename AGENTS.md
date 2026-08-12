# Project Rules

## Build & Analysis
- NEVER run `flutter clean` or `dart analyze`.
- RUN `flutter analyze --no-pub ` with 120 seconds timeout for each script only on files changed, instead.

try to run flutter test, as less often as possible, once confirmed a change, no need to run and re run it again, unless you implement a change. 

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
