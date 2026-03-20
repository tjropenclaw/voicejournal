# VoiceJournal — Project Context for Claude Code

## What We're Building
A voice-first daily journal + habit tracker iPhone app.
Instead of writing notes, users journal via an AI phone call and conversation flow.

## Stack
- Expo SDK 55 / React Native / TypeScript
- Node 22 (`/opt/homebrew/opt/node@22/bin`)
- GitHub Actions CI (lint + typecheck on push/PR)

## Project Structure
```
src/
  screens/     # Screen components
  components/  # Reusable UI components
  hooks/       # Custom hooks
  lib/         # API clients, utilities
  types/       # TypeScript types (index.ts)
App.tsx        # Entry point
```

## Key Types (src/types/index.ts)
- `JournalEntry` — id, date, transcript, summary, mood, audioUrl
- `Habit` — id, name, frequency, color, icon
- `HabitLog` — habitId, date, completed, note
- `CallSession` — id, status, startedAt, transcript

## Coding Rules
- TypeScript strict, no `any`
- Functional components + hooks only
- StyleSheet.create for all styles
- Dark theme: background #0f0f0f, text #ffffff, accent #6366f1
- Test-first: write tests before implementation

## CI
- `npm run typecheck` → `npx tsc --noEmit`
- `npm run lint` → eslint

## Definition of Done
1. Tests written and passing (show output)
2. TypeScript clean (`npx tsc --noEmit`)
3. Lint clean
4. PR created with description + screenshots if UI changed
5. CI passing

## Git
- Branch from `main`
- Conventional commits: `feat:`, `fix:`, `chore:`, `refactor:`
- PR description: what changed, why, proof of correctness
