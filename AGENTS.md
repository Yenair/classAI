# Project Rules

## Build & Analysis
- NEVER run `flutter clean` or `dart analyze` or `flutter analyze `

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

When you are done, audit the prompt i sent to you, then check if you have completed the task accurately. Then list what is left to do, from the prompt i gave you.
