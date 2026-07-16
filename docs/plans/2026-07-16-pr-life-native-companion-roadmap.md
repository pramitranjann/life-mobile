# PR Life Native Companion Roadmap

**Date:** 2026-07-16  
**Status:** Direction approved; implementation pending  
**Primary target:** iOS app and iOS widgets  
**Related system:** PR Life web/API in `~/portfolio`

## Product boundary

The PR Life web app remains the source of truth and the place for planning,
projects, calendar management, editing, history, and reports.

The native apps are companions. Their job is to:

- capture thoughts and tasks with minimal friction;
- deliver timely alerts;
- expose glanceable widgets;
- provide Siri, AirPods, Shortcuts, Live Activity, and device integrations;
- perform small, well-bounded actions against the PR Life API; and
- make sync and release state trustworthy.

This roadmap deliberately does **not** add an in-app Today dashboard or recreate
the web application in SwiftUI. When a workflow becomes substantial, the native
app should deep-link to the relevant web page.

## Explicitly deferred

- AirPods heart-rate and HealthKit integration.
- A full iOS Today, Projects, Calendar, History, or Reports interface.
- macOS widget fixes or redesign work.
- Apple Watch and PR Life Pebble work.

## Outcomes

1. Voice, note, and task capture work reliably from the phone, Siri, and AirPods.
2. A capture can be reviewed, corrected, routed to a project, retried, or discarded.
3. Calendar and application alerts are configurable, announced through AirPods,
   and retained in a small native inbox.
4. Widgets preserve useful last-known data and support focused actions.
5. The app reports real sync, configuration, notification, audio-route, and
   installed-build state.
6. SideStore releases can be distinguished from merely refreshed source metadata.

## Architectural principles

- Keep `LifeAPIClient` as the single authenticated API boundary.
- Keep `CaptureCoordinator` responsible for the capture state machine.
- Put reusable selection, notification, sync, and capture rules in `PRLifeKit`
  with unit coverage.
- Keep credentials in the existing shared Keychain/configuration path.
- Prefer App Intents for Siri, Shortcuts, controls, and interactive widgets.
- Preserve fast capture: review-before-upload must be optional; the default can
  remain automatic upload after transcription.
- Never label the app `SYNCED` unless a real operation succeeded.
- Preserve data during upgrades and SideStore re-signing.

---

## Phase 0 — Trust and diagnostics foundation

Build observability before adding more asynchronous behavior.

### Work

- [ ] Add a shared `LifeSyncState` model with `idle`, `syncing`, `synced`,
  `offline`, `notConfigured`, `authenticationFailed`, and `failed` states.
- [ ] Track last successful API contact, last attempted sync, current error,
  and pending capture count.
- [ ] Replace the static `SYNCED` label in the iOS capture screen with real state.
- [ ] Add a compact Diagnostics section to `Devices_` containing:
  - installed marketing version and bundle build;
  - app bundle identifier after SideStore rewriting;
  - latest published SideStore version/build;
  - API configuration and authenticated connectivity status;
  - widget configuration status;
  - notification authorization status and scheduled-reminder count;
  - active audio input when available.
- [ ] Add `Check for update` and `Install latest build` actions. The latter opens
  the current SideStore source or release IPA without deleting the installed app.
- [ ] Extend `scripts/release.sh` verification to inspect the built IPA version,
  widget version, architecture, ZIP integrity, size, and SHA-256 before publishing.
- [ ] Make the release description human-readable rather than only `Build X (Y)`.

### Likely files

- `App/Screens/MainView.swift`
- `App/Screens/DevicesView.swift`
- `App/CaptureEnvironment.swift`
- `Sources/PRLifeKit/API/LifeAPIClient.swift`
- `Sources/PRLifeKit/Model/LifeSyncState.swift` (new)
- `scripts/build-ipa.sh`
- `scripts/release.sh`
- `sidestore/apps.json`

### Acceptance gates

- [ ] Offline mode never displays `SYNCED`.
- [ ] A 401 is distinguishable from a network outage and missing configuration.
- [ ] The phone screen shows the installed build, not only the source-catalog build.
- [ ] Release automation fails before publishing if app and widget versions differ.

---

## Phase 1 — AirPods capture reliability

Make AirPods Pro 3 the best voice-capture path while retaining built-in microphone
and older Bluetooth fallbacks.

### Work

- [ ] Add iOS 26 high-quality Bluetooth recording using
  `bluetoothHighQualityRecording` with `allowBluetoothHFP` fallback.
- [ ] Use an audio-session mode compatible with high-quality Bluetooth recording;
  do not silently retain `.measurement` if it prevents the feature.
- [ ] Detect and display the selected input, for example `AIRPODS PRO 3_` or
  `IPHONE MIC_`.
- [ ] Add an input picker when multiple microphones are available.
- [ ] Observe audio-route changes and interruptions.
- [ ] If AirPods disconnect during capture, stop and persist the partial capture
  safely. Offer resume/retry instead of losing the recording.
- [ ] Handle calls, Siri interruptions, media playback, and app backgrounding
  without leaving a capture stuck in `recording` or `processing`.
- [ ] Add restrained start, stop, saved, and failure cues that are audible through
  AirPods without contaminating the recorded audio.
- [ ] Record the input route on `CaptureRecord` for diagnostics.
- [ ] Preserve the existing built-in microphone path on iOS 17–25.

### Likely files

- `App/Capture/AVAudioRecorderService.swift`
- `Sources/PRLifeKit/Capture/AudioRecording.swift`
- `Sources/PRLifeKit/Capture/CaptureCoordinator.swift`
- `Sources/PRLifeKit/Model/CaptureRecord.swift`
- `App/CaptureEnvironment.swift`
- `App/Screens/MainView.swift`

### Acceptance gates

- [ ] AirPods Pro 3 can be selected and identified on the physical iPhone.
- [ ] Recorded speech transcribes successfully from the AirPods input.
- [ ] Disconnecting either one or both AirPods never loses the audio captured so far.
- [ ] Locking the phone during recording preserves the capture.
- [ ] Built-in mic capture still passes the existing device QA checklist.

---

## Phase 2 — Capture modes, editing, and Siri

Bring the macOS quick-note/task capability to iOS without adding a native planning
workspace.

### Work

- [ ] Add three focused capture modes: `VOICE_`, `NOTE_`, and `TASK_`.
- [ ] Reuse `LifeAPIClient.createTextEntry` and `createTask` rather than adding
  parallel networking code.
- [ ] Allow optional project/context selection before saving.
- [ ] Add an optional review-before-upload preference for voice captures.
- [ ] Allow editing the transcript and project while a capture is pending.
- [ ] Provide explicit `SAVE_`, `RETRY_`, and `DISCARD_` actions for recoverable
  captures.
- [ ] Preserve automatic upload as the default fast path.
- [ ] Add Siri/App Intents:
  - `Start PR Life capture` with context;
  - `Stop PR Life capture`;
  - `Add a note to PR Life` with dictated content and optional project;
  - `Add a task to PR Life` with title and optional project/due date;
  - `What's next in PR Life?` returning the next event/top task;
  - `Mark a PR Life task complete`.
- [ ] Return spoken Siri confirmations such as `Saved to PR Life — Work` and
  clear spoken failure messages.
- [ ] Add alternate phrases and Shortcut metadata for natural discovery.

### Likely files

- `App/Screens/MainView.swift`
- `App/Theme/Components/CaptureRow.swift`
- `App/Intents/StartCaptureIntent.swift`
- `App/Intents/StopCaptureIntent.swift`
- `App/Intents/PRLifeShortcuts.swift`
- `App/Intents/AddNoteIntent.swift` (new)
- `App/Intents/AddTaskIntent.swift` (new)
- `App/Intents/NextInLifeIntent.swift` (new)
- `App/Intents/CompleteTaskIntent.swift` (new)
- `Sources/PRLifeKit/Capture/CaptureCoordinator.swift`
- `Sources/PRLifeKit/API/LifeAPIClient.swift`

### Acceptance gates

- [ ] Note and task creation appear on the web app through the existing API.
- [ ] Siri works through AirPods while the phone is locked where iOS permits it.
- [ ] Every Siri write confirms success only after the API or durable local queue succeeds.
- [ ] Failed voice transcription keeps the original audio available for retry.
- [ ] The normal hold-to-record flow remains as fast as it is today.

---

## Phase 3 — Notification controls, AirPods announcements, and inbox

Improve local notification usefulness independently of APNs.

### Work

- [ ] Add separate controls for calendar reminders and application alerts.
- [ ] Make calendar lead time configurable: at minimum `At time`, `10 min`,
  `30 min`, and `1 hour`.
- [ ] Make the all-day reminder time configurable.
- [ ] Add quiet hours and an explicit Time Sensitive toggle/explanation.
- [ ] Add `Send test notification` and show the scheduled reminder count.
- [ ] Mark only genuinely imminent calendar/application alerts as Time Sensitive.
- [ ] Ensure supported alerts are eligible for Siri Announce Notifications through
  AirPods when the user enables the system feature.
- [ ] Add a focused notification inbox containing server notification history,
  read/unread state, timestamp, and destination link.
- [ ] Keep the inbox limited to alerts; do not turn it into a Today dashboard.
- [ ] Deep-link notification taps to the program source or the relevant PR Life
  web route.
- [ ] Preserve installation-local delivery cursors so one device cannot suppress
  another device's delivery.

### Likely files

- `App/Screens/DevicesView.swift`
- `App/Screens/NotificationInboxView.swift` (new)
- `App/PRLifeMobileApp.swift`
- `Sources/PRLifeKit/Notifications/UserNotificationPresenter.swift`
- `Sources/PRLifeKit/Notifications/LifeEventReminderService.swift`
- `Sources/PRLifeKit/Notifications/LifeNotificationService.swift`
- `Sources/PRLifeKit/Model/LifeNotificationSettings.swift` (new)

### Acceptance gates

- [ ] A test alert is announced through AirPods when Announce Notifications is enabled.
- [ ] Quiet hours suppress non-urgent alerts.
- [ ] Changing lead time replaces existing event requests without duplicates.
- [ ] Inbox history remains available after the banner is dismissed.
- [ ] Notification controls are comprehensible when permission is denied or provisional.

---

## Phase 4 — APNs feasibility gate and true push delivery

True terminated-app delivery requires a provisioning profile that authorizes the
`aps-environment` entitlement. SideStore re-signing may remove or fail to authorize
that entitlement. Do not build the backend push system until the installed app is
audited on the physical phone.

### Gate A: installed entitlement audit

- [ ] Add the Push Notifications capability to a test branch/build.
- [ ] Install through the same SideStore workflow used in production.
- [ ] Inspect the installed app signature and provisioning profile.
- [ ] Confirm `aps-environment` survives signing and
  `registerForRemoteNotifications()` returns a device token.
- [ ] Capture and surface `didFailToRegisterForRemoteNotificationsWithError`.

### Decision

- If the gate passes, implement APNs below.
- If the gate fails, keep authenticated polling + local reminders + email as the
  supported delivery system. Revisit APNs only after adopting a compatible paid
  Developer Program/provisioning path. Do not ship non-functional push code.

### APNs implementation if Gate A passes

- [ ] Add per-installation device registration, token rotation, environment, and
  last-seen fields to the PR Life backend.
- [ ] Add authenticated register/unregister endpoints.
- [ ] Register on app launch and upload the current device token.
- [ ] Send APNs after the backend durably creates a `life_notifications` record.
- [ ] Include notification ID, kind, destination URL, and dedupe metadata.
- [ ] Remove invalid tokens based on APNs responses.
- [ ] Keep local cursor deduplication so polling and APNs cannot double-deliver.
- [ ] Add a server-side test-push endpoint protected by PR Life authentication.

### Acceptance gates

- [ ] An application alert reaches the phone while PR Life is terminated.
- [ ] Token rotation does not create duplicate installation records.
- [ ] Invalid tokens are retired.
- [ ] APNs and later foreground polling produce one visible alert, not two.
- [ ] Notification taps open the intended destination.

---

## Phase 5 — Dependable and interactive widgets

Keep widgets useful during temporary failures and add only small actions appropriate
for the native companion role.

### Work

- [ ] Store the last successful event/task widget snapshot with `generatedAt`.
- [ ] On fetch failure, render last-known data with `UPDATED 18M AGO` or `STALE_`
  instead of replacing everything with an empty offline screen.
- [ ] Keep setup/authentication failure visually distinct from temporary network failure.
- [ ] Add context-specific deep links for event, task, capture, settings, and web routes.
- [ ] Add interactive widget actions where the OS permits:
  - complete a task;
  - start a voice capture;
  - add a quick note;
  - open the relevant event/task on the web.
- [ ] Make write actions durable and idempotent; never optimistically report completion
  if the API write was not accepted or queued.
- [ ] Trigger targeted timeline reloads after successful writes and capture uploads.

### Likely files

- `Widgets/UpcomingWidget.swift`
- `Widgets/UpcomingWidgetViews.swift`
- `Widgets/PRLifeWidgetsBundle.swift`
- `Sources/PRLifeKit/Cache/LifeSnapshot.swift`
- `Sources/PRLifeKit/Cache/LifeSnapshotStore.swift`
- `App/Intents/CompleteTaskIntent.swift`
- `App/Intents/AddNoteIntent.swift`
- `App/Intents/StartCaptureIntent.swift`

### Acceptance gates

- [ ] A network outage preserves useful last-known widget content.
- [ ] Stale data is clearly labelled and never presented as freshly synced.
- [ ] Task completion updates the web app and then refreshes the widget.
- [ ] Starting capture from a widget works from cold launch and lock screen where allowed.
- [ ] Every widget family passes physical-device visual QA.

---

## Phase 6 — Integrated QA and release

### Automated gates

- [ ] `swift test`
- [ ] iOS simulator build with code signing disabled.
- [ ] macOS app build to prove shared-kit changes do not regress it.
- [ ] IPA ZIP integrity, version/build, architecture, entitlements, and checksum checks.
- [ ] API request/decoding tests for every new endpoint and write action.
- [ ] State-machine tests for interruption, disconnect, retry, deduplication, and cursor behavior.

### Physical-device matrix

- [ ] Built-in iPhone microphone.
- [ ] AirPods Pro 3 high-quality input.
- [ ] AirPods removed during an active capture.
- [ ] Phone locked during capture.
- [ ] Siri commands through AirPods from warm and cold app states.
- [ ] Announce Notifications enabled and disabled.
- [ ] Wi-Fi, cellular, airplane mode, expired token, and server error.
- [ ] Widget small, medium, large, inline, and rectangular families.
- [ ] SideStore install-over-existing-app with local captures preserved.
- [ ] Installed version verified from the device, not only from the source listing.

### Release sequence

Ship in small releases rather than one large build:

1. **Trust release:** real sync status, diagnostics, and SideStore build verification.
2. **AirPods release:** high-quality recording and route-change recovery.
3. **Capture release:** note/task modes, editing, and expanded Siri actions.
4. **Alerts release:** notification controls, announcements, and inbox.
5. **Push release:** APNs only if the SideStore entitlement gate passes.
6. **Widget release:** cached data, deep links, and interactive actions.

Each release must be installed over the current SideStore build and verified on the
physical phone before the next phase begins.

## Definition of done

The roadmap is complete when the iOS app remains a focused companion that can
capture and react hands-free, alerts reliably within the supported signing model,
keeps widgets useful during failures, and accurately explains its own sync and
installed-build state—without duplicating the PR Life web workspace.
