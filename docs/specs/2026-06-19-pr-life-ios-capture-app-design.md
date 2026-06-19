# PR Life iOS Capture App — V1 Design

**Date:** 2026-06-19
**Status:** Approved (design)
**Scope:** First of three companion-app pieces. macOS app and the shared WidgetKit
extension are separate, later specs.

## Goal & Boundary

Provide the fastest possible path from a thought to a captured PR Life entry,
including the ability to start a capture from the lock screen. The app records
audio reliably, transcribes it on-device, and POSTs the resulting text to the
existing `/api/life/entries` endpoint.

The PR Life web app remains the brain (task management, projects, memory,
journaling, planning, AI processing). The iOS app is a capture + display layer
only. It does **not** duplicate web-app features.

**Success criterion:** the user can capture a thought in under two seconds,
including from the lock screen, and have it land in PR Life as a voice entry.

## Chosen Architecture: On-device transcription, reliable (option-2-grade) recording

Decided in brainstorming: use on-device transcription (no backend transcription
pipeline) but record audio with the same reliability we would have built for a
server-upload design, so it survives lock / screen-off / pocket.

```
Trigger (button | Live Activity | App Intent | Action Button)
  -> AudioRecorder writes .m4a to the app container
     (AVAudioSession record category + "audio" background mode -> survives lock)
  -> on stop: Capture.status = .processing
  -> Transcriber (SFSpeechRecognizer) transcribes the recorded file -> text
  -> Capture.status = .uploading
  -> LifeAPIClient POST { content, source: "voice", projectSlug: context }
  -> Capture.status = .done
     (failure -> .failed, queued, retried on reconnect)
```

Status badges (`PROCESSING_` / `DONE_`) are **local** states, so no database
status column is needed. The local capture store is the source of truth for the
history list (works across days without a new server endpoint); the server only
receives the transcribed text.

### Why this works on the backend with zero data changes

- `/api/life/entries` (`POST`) already accepts `{ content, source: "voice",
  projectSlug }`.
- `isAuthenticatedLifeRequest` already accepts `Authorization: Bearer <token>`
  in addition to the same-origin admin cookie, so a native client can
  authenticate without cookies.
- The `entries` table already stores `content`, `source`, `project_slug`,
  `local_date`, `created_at`.

## Platform / Project

- New Xcode project, SwiftUI, **iOS 17.0+** (required for interactive Live
  Activities and App Intents-based lock-screen start).
- Location: `~/Developer/PRLifeMobile` (outside the portfolio repo).
- Two targets:
  - **PRLifeMobile** — the app.
  - **PRLifeMobileWidgets** — Live Activity widget extension (ActivityKit +
    WidgetKit). Hosts the Live Activity now; home-screen widgets are deferred.
- Fonts bundled: Clash Display (Fontshare 400/500/600/700) and DM Mono (Google
  300/400/500), matching the portfolio.

## Modules

Each module has one purpose, a well-defined interface, and is testable in
isolation.

1. **PRLifeTheme** — design tokens (colors, typography, spacing) plus square-corner
   primitives: `SectionLabel`, `StatusBadge`, `SquareToggle`, `RecordButton`.
   Depends on nothing.
2. **AudioRecorder** — wraps `AVAudioSession` (record category, `audio`
   background mode) and `AVAudioRecorder` writing `.m4a` to the app container.
   Exposes start/stop, a duration timer, and recording state; handles audio
   interruptions and route changes. Behind a protocol so it can be faked in
   tests.
3. **Transcriber** — `SFSpeechRecognizer` transcribing a recorded file to text.
   Behind a protocol; mockable.
4. **CaptureStore** — local persistence (SwiftData) of:
   `Capture { id, createdAt, duration, context, audioURL, transcript, status,
   serverEntryId }`. Source of truth for the history list. Owns status
   transitions.
5. **LifeAPIClient** — Bearer-token `POST` to `/api/life/entries`; upload queue
   with retry via `NWPathMonitor`; honors the "Upload on WiFi only" setting.
   Config (base URL + token) stored in Keychain.
6. **CaptureCoordinator** — the handoff's required input-source abstraction. A
   single `PRLifeAction.startCapture(context)` / `.stopCapture` that the in-app
   button, Live Activity, App Intent/Shortcut, and Action Button all call.
   Pebble / Apple Watch slot in here later without touching the rest of the app.
7. **Live Activity + App Intents** — lock-screen and Dynamic Island recording UI
   with an interactive **Stop** control, plus `StartCaptureIntent(context)` for
   Action Button / Shortcuts / lock-screen start, and `StopCaptureIntent`.

## Screens

Recreated from the handoff mockups in SwiftUI, preserving the PR Life visual
identity (square corners, 1px borders, no shadows, signal red `#ff3120`).

- **Main App** (`ios-main-app`): `LIFE_` header + sync dot; full-width
  push-to-talk Record button; `CAPTURES_` list with per-row status badge,
  progress bar while processing, duration · context, and transcript snippet.
  Data comes from CaptureStore.
- **Devices** (`ios-devices`): PR Life API connection + Sync; Pebble card
  (*Not paired*, future-stub, no CoreBluetooth yet); Recording settings with
  real custom **square** toggles — Background recording, Upload on WiFi only —
  plus Audio quality; Apple Watch card (*Coming soon*).
- **Lock screen** (`ios-lock-screen`): the recording state is the **Live
  Activity** (system-rendered), not a hand-built screen. The stats and
  accessoryRectangular lock-screen widgets are deferred to the Widgets piece.

## Configuration & Auth

- API base URL + bearer token stored in **Keychain**, editable on the Devices
  screen (localhost for dev, the deployed Vercel URL for prod).
- **Backend change (approved):** add a dedicated `LIFE_MOBILE_TOKEN` rather than
  reusing the cron secret on a mobile device. Small change in the portfolio repo:
  - `lib/life/env.ts`: read and expose `LIFE_MOBILE_TOKEN`.
  - `lib/life/auth.ts`: accept a Bearer token matching either the cron secret or
    the mobile token (constant-time compare).
  This is the only change to the portfolio repo for V1.

## Permissions (Info.plist)

- `NSMicrophoneUsageDescription`
- `NSSpeechRecognitionUsageDescription`
- Background mode: `audio`

## Capture Metadata

Each capture carries useful metadata locally, aligned with the handoff example:
`source` (e.g. `ios_app`, later `ios_pebble`), `input_type`, `context`,
`timestamp`, `duration_seconds`, `device`, `status`. Only `content`, `source`,
and `projectSlug` (context) are sent to the server in V1; the rest stays local
for the history view and future use.

## Testing

- **CaptureStore** — status transition correctness
  (recording -> processing -> uploading -> done / failed).
- **LifeAPIClient** — request building, auth header, queue + retry, WiFi-only
  gating (with a fake reachability source).
- **CaptureCoordinator** — every input source maps to the same action.
- **Transcriber** — with a mock recognizer.
- **AudioRecorder** — behind a protocol with a fake; real recording verified
  manually on device.

## Out of Scope for V1 (architected-for, not built)

- Home-screen and accessoryRectangular **widgets** (separate Widgets piece).
- The stats lock-screen widget.
- **CoreBluetooth / Pebble** (the CaptureCoordinator is designed to accept it).
- **Apple Watch**.
- The **macOS** companion app (its own later spec).

## Open Items (resolve during implementation)

- Final bundle identifier / App Group ID for app <-> widget extension sharing.
- Audio quality preset values behind the "Audio quality" setting.
