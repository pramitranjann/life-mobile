# PR Life iOS — V2 Display Layer (Widgets) Design

**Date:** 2026-06-20
**Status:** Approved (design)
**Builds on:** the v1 iOS capture app (`docs/specs/2026-06-19-pr-life-ios-capture-app-design.md`). Reuses `PRLifeKit`, the `PRLifeWidgets` extension (which already hosts the recording Live Activity), the App Group, fonts, and design tokens.
**Gate:** v1 physical-device QA (`docs/v1-device-qa-checklist.md`) should pass before V2 implementation ships; V2 design/spec/plan is independent of that and can proceed in parallel.

## Goal & Boundary

Turn the iOS app from capture-only into a glanceable **window into PR Life** by adding WidgetKit widgets that surface upcoming calendar events and due tasks. The web app remains the brain; widgets are a read-only display surface.

**In scope:** home-screen widgets (`systemSmall`, `systemMedium`, `systemLarge`) and lock-screen accessory widgets (`accessoryRectangular`, `accessoryInline`) showing events + tasks. Widgets are tappable (open the app via `widgetURL`).

**Explicitly out of scope (V2):** in-app Today view/tab, background refresh (`BGAppRefreshTask`), interactive/Button widgets and write actions (completing tasks from a widget), macOS widgets. These are potential V3+.

**Success criterion:** the user can see their next events and top due tasks at a glance from the home screen and lock screen, without opening the app.

## Chosen Architecture: widget fetches directly

Decided in brainstorming. The widget extension fetches its own data rather than relying on the app to pre-populate a cache.

```
Widget TimelineProvider.getTimeline
  -> build LifeAPIClient from SHARED-KEYCHAIN config (base URL + LIFE_MOBILE_TOKEN)
  -> async fetchEvents(date: today) + fetchTasks(status: active)
  -> one TimelineEntry { events, tasks, generatedAt }
  -> Timeline(policy: .after(now + 30 min))
  -> render per widgetFamily
```

- No dependency on the app being opened for data to appear. The app still calls `WidgetCenter.shared.reloadAllTimelines()` after a capture upload and on foreground to nudge fresher data.
- Error / not-configured / offline: render a tasteful placeholder ("Set up PR Life in the app" or last-known empty state); never crash or show stale-looking garbage. `.notConfigured` (already modeled in `LifeAPIClient`) maps to the setup placeholder.
- Refresh cadence: WidgetKit timeline reload every ~30 min (OS-throttled) plus app-triggered reloads. This matches the spec's "refresh periodically + on app foreground + on capture uploaded."

### Why this needs shared Keychain

The widget runs in the `PRLifeWidgets` extension process and must read the API base URL + bearer token, which today live in the app-only Keychain. We move them into a shared **keychain-access-group** so both processes read the same encrypted items (chosen over App Group `UserDefaults` to keep the bearer token in the Keychain, not a plist).

## Backend (no changes)

Reuses existing authenticated GET endpoints (auth: `Authorization: Bearer <LIFE_MOBILE_TOKEN>`, already wired in `~/portfolio/lib/life/auth.ts`):

- `GET /api/life/calendar[?date=YYYY-MM-DD]` → `{ localDate, timezone, events: CalendarEventRecord[] }`.
  `CalendarEventRecord`: `{ id, user_id, title: string|null, calendar_id, calendar_name, start_time: string|null (ISO), end_time: string|null, local_date, ... }`.
- `GET /api/life/tasks?status=active` → `{ tasks: TaskRecord[] }`.
  `TaskRecord`: `{ id, user_id, title: string, project_slug: string|null, status: "open"|"in_progress"|"done"|"dismissed", priority: "high"|"medium"|"low", due_local_date: string|null, ... }`.

No backend changes required for V2.

## New in `PRLifeKit` (platform-free, TDD)

1. `Model/LifeEvent.swift` — `struct LifeEvent: Identifiable, Codable, Sendable { id: String; title: String; start: Date?; end: Date?; calendarName: String? }`. Decoded from the calendar envelope; `start_time`/`end_time` parsed as ISO8601 (handle null title → "Untitled"). Provide a custom decoder or a mapping init from the raw record so snake_case + ISO dates are handled in one place.
2. `Model/LifeTask.swift` — `struct LifeTask: Identifiable, Codable, Sendable { id: String; title: String; priority: TaskPriority; dueLocalDate: String?; projectSlug: String?; status: String }` with `enum TaskPriority: String { case high, medium, low }` (+ a UI color hint left to the widget layer via tokens).
3. `API/LifeAPIClient` additions:
   - `func fetchEvents(date: String? = nil) async throws -> [LifeEvent]` — GET `/api/life/calendar`, decode `{events:[…]}`.
   - `func fetchTasks() async throws -> [LifeTask]` — GET `/api/life/tasks?status=active`, decode `{tasks:[…]}`.
   - Both reuse the existing `resolvedConfiguration()` / Bearer-auth / `.notConfigured` / non-2xx → `.server` / undecodable → `.decoding` logic from `upload`/`deleteEntry`.
4. `Model/LifeDashboard.swift` — pure, testable selection helpers used by every widget family:
   - `nextEvents(_ events: [LifeEvent], limit: Int, now: Date) -> [LifeEvent]` (upcoming, sorted by start).
   - `topTasks(_ tasks: [LifeTask], limit: Int) -> [LifeTask]` (priority then due date).

## Widget implementation (`PRLifeWidgets` extension)

- A single `UpcomingWidget: Widget` (StaticConfiguration) with `supportedFamilies`: `.systemSmall`, `.systemMedium`, `.systemLarge`, `.accessoryRectangular`, `.accessoryInline`. Registered in `PRLifeWidgetsBundle` alongside the existing `RecordingLiveActivity`.
- One `TimelineProvider` (`placeholder`, `getSnapshot` with sample data for the gallery, `getTimeline` doing the live fetch). One `TimelineEntry { date, events, tasks, state }` where `state` ∈ `{ ok, notConfigured, failed }`.
- A family-switching SwiftUI view (`@Environment(\.widgetFamily)`) rendering per the handoff specs:
  - **systemSmall:** "NEXT_" + next event name (Clash 14) + time/countdown (DM Mono, accent) + date footer.
  - **systemMedium:** header (day/date) + 2 columns — events (left) / tasks (right) with priority dots and opacity steps.
  - **systemLarge:** Events_ section (3 rows, next in accent) + hairline + Due today_ section (3 rows w/ priority dots).
  - **accessoryRectangular:** next event title + time (mono).
  - **accessoryInline:** next event one-liner.
- Visual language reuses `PRLifeTokens` + a widget-target copy of the `Theme`/`Color(hex:)` bridge + the bundled Clash Display / DM Mono fonts. Square corners, 1px borders, no shadows, signal red `#FF3120`; priority dots high `#FF6C61` / medium `#F5A623` / low|none muted.
- `widgetURL(URL(string: "prlife://open"))` (or context-specific) so tapping opens the app (deep-link handling already exists in `CaptureEnvironment.handleDeepLink`).

### Design provenance
- **systemSmall / systemMedium / systemLarge:** built 1:1 from the shared handoff designs — `CODEX_PROMPT.md` ("Widget — Small/Medium/Large" sections), `README.md` sections 7–9, and `screens/widget-{small,medium,large}.html` + `screenshots/`.
- **accessoryRectangular / accessoryInline:** no exact event/task mockup exists in the handoff (its lock-screen mockup, `ios-lock-screen`, is the recording-status + stats widgets, which are capture-oriented). These accessory families are **derived from the existing design language** (the small widget's "NEXT_" event block adapted to the tinted accessory family) — approved by the user 2026-06-20.

## Shared-Keychain change

- Add the **Keychain Sharing** capability + `keychain-access-groups` entitlement to BOTH targets (`App/PRLifeMobile.entitlements`, `Widgets/PRLifeWidgets.entitlements`); access group e.g. `$(AppIdentifierPrefix)com.pramitranjan.prlife.shared`. Wire via existing `CODE_SIGN_ENTITLEMENTS` in `project.yml`.
- Update `App/Net/KeychainConfig.swift` to set `kSecAttrAccessGroup` on its queries so items are written to / read from the shared group. The widget uses the same `KeychainConfig` (move it so the widget target can compile it, or add a small shared accessor) to build the `LifeAPIClient.configurationProvider`.
- User re-saves Base URL + Token once in the Devices screen after the change (items migrate to the shared group).

## Testing

- **PRLifeKit (`swift test`, `MockURLProtocol`):**
  - `LifeEvent`/`LifeTask` decoding from the real `{events:[…]}` / `{tasks:[…]}` JSON envelopes (incl. null title, null times, ISO8601 parsing).
  - `fetchEvents`/`fetchTasks`: correct URL + Bearer header, envelope decoding, `.notConfigured` when unset, non-2xx → `.server`.
  - `LifeDashboard.nextEvents`/`topTasks` selection + ordering.
- **Widget rendering:** build the extension, add each family in the simulator, screenshot to verify layout. Live data fetch + 30-min refresh + lock-screen accessory validated on a physical device with a valid token (widget networking + Keychain sharing can't be fully exercised in unit tests).

## Open Items (resolve during implementation)

- Whether `KeychainConfig` is duplicated into the widget target or extracted to a shared file/target-membership (prefer target-membership of the one file).
- The exact `widgetURL` scheme(s) (single `prlife://open` vs per-section deep links).
- Date/time formatting + relative countdown ("22m") helper location (widget layer, using `Date` styles).
