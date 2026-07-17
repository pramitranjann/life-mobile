# PROJECT.md — PRLifeMobile

<!-- Live memory for this repo. Every agent reads this first, updates it last.
     Keep under 150 lines. Replace superseded lines; don't append forever. -->

## Goal
Native companions (iOS app + widgets + Live Activity, Mac menu-bar app +
widgets) for PR Life — capture voice/notes/tasks into the PR Life web API
from anywhere, and glance today's events/tasks without opening the web app.

## Non-goals
- Reimplementing the web dashboard natively (month/report/studio views stay web).
- Offline-first task management — native is capture + glance; the server owns state.

## Current state (2026-07-17)
Works: voice/note/task capture, retry/review flows, upcoming + quick-capture
widgets, Live Activity, Mac popover with quick add + hotkeys, snapshot sync.
Just landed: full UI fidelity pass against the web `.life-shell` reference —
shared Theme/tokens moved into PRLifeKit, circle checkboxes (Mac rows can now
complete tasks), neutral segmented controls, type-scale floors, pressed
states, contrast fixes, Live Activity re-skin. All 4 targets build.

## Decisions (with why)
- 2026-07-17 — The web app's `.life-shell` CSS is the design source of truth;
  DESIGN.md in this repo is the native translation. Why: native had drifted
  (wrong accent hex, capsules, squares) with no written law.
- 2026-07-17 — One SwiftUI Theme bridge lives in PRLifeKit; per-target Theme
  files deleted. Why: two copies had already diverged (accentSoft 0.07 vs 0.10).
- 2026-07-17 — Mono-first type: `Theme.body` aliases DM Mono. Why: web sets
  DM Mono as the default family; SF body text read as a different product.
- 2026-07-17 — Solid accent fill reserved for live/recording states; primary
  actions are accent outlines. Why: mirrors web `.life-btn.primary` vs
  `.life-mic.is-live` accent discipline.

## Open threads
- Widget view bodies are still ~80% duplicated between Widgets/ and
  MacWidgets/ (formatting + primitives are shared now; the family bodies
  differ in interactivity/diagnostics — merge only if they keep drifting).
- Mac popover TaskRow completion has no error toast — a failed completion
  silently restores the row on refresh.
- Hardware rows (Desk Dock, NFC, Pebble) are roadmap placeholders in both
  Devices screens.

## Gotchas
- project.yml is the build source — `xcodegen` after adding/removing files,
  or the .xcodeproj still references ghosts. Widget targets list individual
  App/MacApp files as sources; check there when a shared file moves.
- Widget targets bundle their own font copies (App/Resources/Fonts,
  MacApp/Resources/Fonts); MacWidgets calls FontRegistration.registerAll().
- The iOS toolbar link labeled "Settings_" opens DevicesView (file name is
  historical).
- LifeSnapshot decodes both `generatedAt` and legacy `lastSync` keys — keep
  both when touching the codec, installed widgets may be older.

## Next action
Run the app + widgets in the simulator and screenshot each surface against
the web app at phone width (the fidelity pass changed nearly every view and
has only been build-verified, not eyeballed).
