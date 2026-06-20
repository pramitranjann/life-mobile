# PR Life — macOS Companion App: Design Spec

**Date:** 2026-06-20
**Status:** Approved (brainstorming) → ready for implementation plan
**Repo:** `~/Developer/PRLifeMobile` (monorepo, branch `main`, no remote)
**Related:** iOS spec `docs/specs/2026-06-19-pr-life-ios-capture-app-design.md`; handoff `docs/macos-companion-handoff.md`

---

## 1. Summary

PR Life is a personal life OS; the web app (`~/portfolio`, `/life` + `/api/life`) is the brain. The macOS companion is a **quiet, menu-bar-first system utility**: it shows today's upcoming events and due tasks at a glance, offers voice Quick Capture via desktop mic + global hotkeys, and exposes WidgetKit widgets. It is **display-first** (the inverse of the capture-first iOS app) and must not duplicate web-app features (tasks/projects/journaling/AI live in the web app).

**V1 scope (approved): Full + widgets.**
- Menu-bar popover + main window (Today / Captures / Devices tabs)
- Live events/tasks/sync read from the backend
- Desktop-mic Quick Capture + global hotkeys routed through the existing `CaptureCoordinator`
- WidgetKit widgets (small / medium / large)

---

## 2. Decisions locked in brainstorming

1. **Monorepo target** — add `PRLifeMac` + `PRLifeMacWidgets` to the existing repo/`project.yml` (not a sibling repo). Reuse `PRLifeKit` wholesale.
2. **Global hotkeys via an in-house Carbon `RegisterEventHotKey` wrapper** behind a `GlobalHotKeyRegistering` protocol. No third-party dependency, no Accessibility permission, fixed chords as speced, TDD-friendly seam.
3. **"Upcoming" is today-only in V1** — `/api/life/calendar` returns one `local_date` per call and every speced screen says "Today." Multi-day rollup deferred to v2.
4. **Capture is toggle, not push-to-talk** — press hotkey / click Quick Capture button to start; same hotkey, Stop button, or `Esc` to stop. (Holding a 3-key chord to talk is ergonomically poor; desk-dock vision is "press → speak → press.")
5. **App-writes / widget-reads via a shared snapshot** — the app fetches and writes a `LifeSnapshot` JSON into the App Group container, then calls `WidgetCenter.reloadAllTimelines()`. Widgets never hit the network.

---

## 3. Backend API (confirmed from route files)

Auth: `Authorization: Bearer <LIFE_MOBILE_TOKEN>` (`~/portfolio/lib/life/auth.ts` accepts cron secret OR `LIFE_MOBILE_TOKEN`).

- **`GET /api/life/calendar?date=YYYY-MM-DD`** → `{ localDate, timezone, events: CalendarEventRecord[] }`, one local date only, ordered by `start_time` asc.
  `CalendarEventRecord`: `id`, `user_id`, `title?`, `calendar_id?`, `calendar_name?`, `location?`, `notes?`, `html_link?`, `start_time?` (ISO), `end_time?` (ISO), `all_day: bool`, `source`, `local_date`, `updated_at`, `synced_at`.
- **`GET /api/life/tasks?status=active`** → `{ tasks: TaskRecord[] }`.
  `TaskRecord`: `id`, `user_id`, `title`, `details?`, `project_slug?`, `status` (`open|in_progress|done|dismissed`), `priority` (`high|medium|low`), `due_local_date?`, `source_type`, `created_at`, `updated_at`, `completed_at?`, etc.
- **`POST /api/life/entries`** `{content, source:"voice", projectSlug}` and **`DELETE /api/life/entries/[id]`** — capture upload/delete, already used by iOS via `LifeAPIClient`.

"Due today" = client-side filter `due_local_date == today`. Limit displays to ~3–5 rows per the PRD.

---

## 4. Reuse vs. net-new

### Reused wholesale from `PRLifeKit` (no changes)
`CaptureContext` (quick/work/journal/ideas → `projectSlug`), `CaptureRecord`, `CaptureStatus`, `PRLifeAction`, `LifeAPIClient` (upload/delete + `configurationProvider`), `CaptureCoordinator`, `CaptureActionRouter`, `CaptureControlChannel`, `CaptureStoring`, `AudioRecording`/`Transcribing` protocols, `UploadGate`/`Reachability` protocols, `PRLifeTokens`.

### Re-added in the macOS target (mirror iOS, not shared by iOS target)
`Theme`/`Color(hex:)` bridge + `Theme.mono/display/body`; the four fonts (`ClashDisplay-*`, `DMMono-*`); an `AppGroup` constant (`group.com.pramitranjan.prlife`); `KeychainConfig` (it's `Security`-framework, cross-platform — share the source or re-add).

### Net-new in `PRLifeKit` (platform-free, TDD'd)
- `Model/LifeEvent.swift` — `Codable` for `calendar_events` rows; computed `displayTime`, `isAllDay`; `Identifiable`.
- `Model/LifeTask.swift` — `Codable` for `tasks` rows; `priority`, `dueLocalDate?`, `projectSlug?`; `Identifiable`. (Priority→color mapping stays in the view layer.)
- `LifeAPIClient.fetchEvents(date:) async throws -> [LifeEvent]` and `fetchTasks() async throws -> [LifeTask]` — same Bearer / `configurationProvider` / `.notConfigured` guards as `upload`.
- `Cache/LifeSnapshot.swift` (`{ events, tasks, lastSync }`, `Codable`) + `LifeSnapshotStore` — JSON read/write into the App Group container behind a protocol; unit-tested with a temp dir. Single source the widget and app both read.

### Net-new macOS app-target concretes
- `MacAudioRecorderService: AudioRecording` — `AVAudioRecorder` (no `AVAudioSession` on macOS); mic permission via `AVCaptureDevice.requestAccess(for: .audio)`; writes `.m4a` to a macOS captures-dir helper in the App Group container (no `FileProtection` on macOS).
- `SpeechTranscriber` — port iOS (Speech framework on macOS 14); only the captures-dir reference changes. On-device, 60s watchdog.
- `CaptureStore` — reuse the SwiftData store pattern (`ModelConfiguration(groupContainer:)`) for parity with iOS and the Captures tab.
- `MacCaptureEnvironment` — mirrors iOS `CaptureEnvironment`: one coordinator from `KeychainConfig`; wires `CaptureActionRouter.start/stop`; owns recording state; `UploadGate` with an `NWPathMonitor` reachability.
- `GlobalHotKeyManager: GlobalHotKeyRegistering` — Carbon `RegisterEventHotKey` wrapper; registers ⌃⌥Space/W/J/I → `CaptureContext` → `CaptureActionRouter`. Protocol seam for testability.

---

## 5. Target & project configuration

- `project.yml`: add `deploymentTarget.macOS: "14.0"`; new targets `PRLifeMac` (app, `platform: macOS`) and `PRLifeMacWidgets` (app-extension). Run `xcodegen generate` after manifest changes.
- `SWIFT_VERSION = 5.9`; strict Swift 6 concurrency OFF (consistent with `@MainActor` stores vs `Sendable` protocols).
- Bundle IDs `com.pramitranjan.prlife.mac` / `...mac.widgets`; both members of App Group `group.com.pramitranjan.prlife` (container is per-device — no iOS↔macOS sharing, by design).
- Activation policy **accessory** (menu-bar-first, no permanent Dock icon); main window opens on demand. `MenuBarExtra(...).menuBarExtraStyle(.window)`.
- `PRLifeKit` already declares `platforms: [.iOS(.v17), .macOS(.v13)]` — no package change needed.
- Entitlements: App Group, mic (`com.apple.security.device.audio-input`), Keychain sharing if needed. Info.plist usage strings for mic + speech recognition.

---

## 6. Capture interaction model (toggle)

```
hotkey ⌃⌥W  ─┐
popover btn  ─┼─▶ CaptureActionRouter.start(context)
menu item    ─┘        │
                       ▼
              CaptureCoordinator.handle(.startCapture)  →  MacAudioRecorderService.start()
                       │
        recording state: menu-bar icon red + popover shows elapsed + Stop
                       │
hotkey again / Stop / Esc ─▶ CaptureActionRouter.stop ─▶ .stopCapture
                       ▼
        recorder.stop → SpeechTranscriber → LifeAPIClient.upload(content, projectSlug)
```

`Quick` context carries no `projectSlug`; Work/Journal/Ideas map to their slug (existing `CaptureContext`). Cross-surface stop reuses `CaptureControlChannel` (App-Group flag) exactly as iOS.

---

## 7. Sync & data flow

App fetches events + tasks on: launch, popover open, manual "Sync now," and a periodic timer (~15 min). On success it writes `LifeSnapshot` to the App Group JSON and calls `WidgetCenter.shared.reloadAllTimelines()`. Widgets' `TimelineProvider` reads the snapshot only — never the network. Offline / `.notConfigured` shows the last cached snapshot plus a disconnected sync indicator.

---

## 8. UI surfaces (recreate pixel specs in SwiftUI; do not ship the HTML)

Specs in `~/Downloads/design_handoff_companion_apps/CODEX_PROMPT.md`. Visual language: square corners (radius 0), 1px borders, no shadows, accent `#FF3120`, DM Mono labels/meta, Clash Display headings, SF Pro body, trailing-underscore labels.

- **Screen 4 — MenuBarExtra popover (340pt):** header + sync status; Quick Capture 2×2 (live); Upcoming (today's events, accent bar + countdown on next); Due Today (tasks filtered on `due_local_date == today`, priority dot); footer (Open PR Life / Settings).
- **Screen 5 — Main window · Today (~900pt, min 520pt):** date heading; 2-col Upcoming / Due Today; sync footer.
- **Screen 6 — Main window · Devices (520pt):** live keyboard-shortcut tiles; "coming soon" hardware rows (Desk Dock / NFC / BT·USB); architecture note ("all input sources map to the same internal action system").
- **Captures tab:** local capture history from the store (mirrors the iOS captures list — timestamp, duration, status, context).
- **Widgets (small 158², medium 338×158, large 338×354):** events + tasks from `LifeSnapshotStore`.

---

## 9. Hardware abstraction seam

All inputs route through `PRLifeAction` → `CaptureActionRouter` → `CaptureCoordinator`. Hotkeys are the first non-UI input source. Future NFC/BLE/USB/desk-dock add adapters that emit `PRLifeAction`; no coordinator changes. The Devices tab documents this. **No hardware is built in V1** — the architecture just must not block it.

---

## 10. Settings / config

A SwiftUI `Settings` scene (and the Devices tab "PR Life API" section) to enter base URL + `LIFE_MOBILE_TOKEN` → `KeychainConfig`; Wi-Fi-only toggle (reuses `UploadGate`). Mirrors iOS. `LocalAPIConfig.plist` bundled-defaults pattern optional for dev convenience.

---

## 11. Testing strategy

- **`PRLifeKit` unit tests (must pass via `swift test`):** `LifeEvent`/`LifeTask` decoding against real JSON fixtures derived from the route shapes (incl. null `start_time`/`title`, all-day, missing `due_local_date`); `LifeSnapshotStore` round-trip; `GlobalHotKeyManager` context mapping with a fake registrar.
- **App-target concretes** (mic capture, Speech transcription, Carbon hotkey registration, MenuBarExtra rendering, widget timelines, permission prompts) are runtime/permission-gated → **flagged for manual QA**, per project conventions.
- Build gate: `xcodebuild ... -destination 'platform=macOS'` succeeds. Treat SourceKit "No such module 'PRLifeKit'" / cross-file diagnostics as false positives when `swift test` / `xcodebuild` pass.

---

## 12. Deferred to v2 (explicit non-goals)

Multi-day event rollup; notifications (UserNotifications); user-customizable shortcuts; real hardware (NFC/BLE/USB/desk-dock); upload-retry UI beyond the coordinator's existing retry; iOS↔macOS data sharing (App Group is per-device).

**Timezone note (v2):** the client's "due today" task filter uses the device timezone (`Calendar.current`), while the backend keys `local_date` to the owner's configured timezone. For a single-user, same-timezone setup these agree; if they diverge around midnight the task filter could be off by a day. Events sidestep this by fetching with `date: nil` (server defaults to the owner's today). A v2 fix would carry `localDate`/`timezone` from the API response into the snapshot and filter off that rather than the device clock.

---

## 13. Carry-over notes

- Backend lives on `~/portfolio` branch `life-mobile-token` (mobile bearer token + `DELETE /api/life/entries/:id`); user merges/pushes. Do not commit in `~/portfolio` beyond explicitly-scoped changes; never enable `cacheComponents`.
- Git: never push; local per-task commits during an approved execution loop are authorized (Co-Authored-By trailer); greenfield work stays on `main` locally.
- Process: this spec → `writing-plans` (save to `docs/plans/`) → `subagent-driven-development` (spec-review + code-quality-review on substantive tasks; build/`swift test` as gates; runtime behavior flagged for manual QA). Execution style: inline implementation, reviews batched at the end for heavy multi-task plans.
