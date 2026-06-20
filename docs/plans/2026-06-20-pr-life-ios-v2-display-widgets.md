# PR Life iOS — V2 Display Widgets (Upcoming) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an iOS WidgetKit "Upcoming" widget (home `systemSmall/Medium/Large` + lock-screen `accessoryRectangular/Inline`) that shows upcoming calendar events and due tasks, fetching directly from the backend.

**Architecture:** Direct-fetch — the widget's `TimelineProvider` builds a `LifeAPIClient` from a **shared-Keychain** config and calls the existing `fetchEvents`/`fetchTasks`, rendering per `widgetFamily` with a 30-min refresh. Reuses the already-built `PRLifeKit` (`LifeEvent`, `LifeTask`, `LifeAPIClient.fetchEvents/fetchTasks`) and adds only the missing pieces.

**Tech Stack:** Swift 5.9 / Xcode 26.5, iOS 17, SwiftUI, WidgetKit, Security (Keychain sharing), XcodeGen. No backend changes.

**Spec:** `docs/specs/2026-06-20-pr-life-ios-v2-display-widgets-design.md`

## Already done (DO NOT re-implement — verify only)
Codex already built and tested (41/41 `swift test`): `Sources/PRLifeKit/Model/LifeEvent.swift`, `Model/LifeTask.swift`, `LifeAPIClient.fetchEvents(date:)` + `fetchTasks()`, and `Cache/LifeSnapshot*` (not used by this direct-fetch plan). The iOS app + `PRLifeWidgets` extension build green; the extension currently hosts `QuickCaptureWidget` (a capture launcher) + `RecordingLiveActivity`. This plan ADDS the events/tasks "Upcoming" widget alongside them.

## Conventions
- Kit logic → `swift test` (no sim). Widget/app → `xcodebuild` build + simulator add-widget screenshot; live data needs a device with a valid token (flag, don't block).
- iOS sim destination: `platform=iOS Simulator,name=iPhone 17 Pro` (substitute an available one from `xcrun simctl list devices available`).
- Local per-task commits authorized (no push). End commit bodies with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer.
- Team ID for entitlements/signing is `8QBV8WL699` (already used by the Mac targets in `project.yml`).
- SourceKit "No such module 'PRLifeKit'" diagnostics are false positives when `swift test`/`xcodebuild` pass.

## File Structure
```
Sources/PRLifeKit/Model/LifeDashboard.swift     # NEW: nextEvents()/topTasks() pure selectors
Tests/PRLifeKitTests/LifeDashboardTests.swift    # NEW
App/Net/KeychainConfig.swift                      # MODIFY: shared keychain access group
App/PRLifeMobile.entitlements                     # MODIFY: + keychain-access-groups
Widgets/PRLifeWidgets.entitlements                # MODIFY: + keychain-access-groups
Widgets/Info.plist                                # MODIFY: + UIAppFonts
Widgets/UpcomingWidget.swift                       # NEW: provider + entry + Widget config
Widgets/UpcomingWidgetViews.swift                  # NEW: family-switching SwiftUI views
Widgets/PRLifeWidgetsBundle.swift                  # MODIFY: register UpcomingWidget()
App/Theme/PRLifeTheme.swift                        # (add to widget target via project.yml)
App/Resources/Fonts/*                              # (add to widget target via project.yml)
project.yml                                        # MODIFY: widget target sources/resources + iOS DEVELOPMENT_TEAM
App/CaptureEnvironment.swift                       # MODIFY: WidgetCenter reload after upload
```

---

## Task 1: Kit selection helpers (`LifeDashboard`)

**Files:**
- Create: `Sources/PRLifeKit/Model/LifeDashboard.swift`
- Create: `Tests/PRLifeKitTests/LifeDashboardTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/PRLifeKitTests/LifeDashboardTests.swift`:
```swift
import XCTest
@testable import PRLifeKit

final class LifeDashboardTests: XCTestCase {
    private func ev(_ id: String, _ minsFromNow: Int, _ now: Date) -> LifeEvent {
        LifeEvent(id: id, title: "E\(id)", start: now.addingTimeInterval(Double(minsFromNow) * 60),
                  end: nil, calendarName: nil)
    }

    func test_nextEvents_dropsPastAndSortsByStart() {
        let now = Date()
        let events = [ev("a", 30, now), ev("b", -10, now), ev("c", 5, now)]
        let next = LifeDashboard.nextEvents(events, limit: 5, now: now)
        XCTAssertEqual(next.map(\.id), ["c", "a"])   // past 'b' dropped, sorted ascending
    }

    func test_nextEvents_respectsLimit() {
        let now = Date()
        let events = [ev("a", 5, now), ev("b", 10, now), ev("c", 15, now)]
        XCTAssertEqual(LifeDashboard.nextEvents(events, limit: 2, now: now).map(\.id), ["a", "b"])
    }

    func test_topTasks_ordersByPriorityThenLimit() {
        let t = { (id: String, p: TaskPriority) in
            LifeTask(id: id, title: "T\(id)", priority: p, dueLocalDate: nil, projectSlug: nil, status: "open")
        }
        let tasks = [t("a", .low), t("b", .high), t("c", .medium)]
        XCTAssertEqual(LifeDashboard.topTasks(tasks, limit: 2).map(\.id), ["b", "c"])
    }
}
```

> Verify the exact `LifeEvent`/`LifeTask` initializer signatures first (`grep -n "public init" Sources/PRLifeKit/Model/LifeEvent.swift Sources/PRLifeKit/Model/LifeTask.swift`) and adjust the test's constructors to match before running. If `TaskPriority` lives on `LifeTask` as a nested type, use `LifeTask.TaskPriority`.

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter LifeDashboardTests`

- [ ] **Step 3: Implement**

`Sources/PRLifeKit/Model/LifeDashboard.swift`:
```swift
import Foundation

/// Pure selection helpers shared by every widget family.
public enum LifeDashboard {
    /// Upcoming events (start in the future), sorted ascending, capped at `limit`.
    public static func nextEvents(_ events: [LifeEvent], limit: Int, now: Date = Date()) -> [LifeEvent] {
        events
            .filter { ($0.start ?? .distantPast) >= now }
            .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
            .prefix(limit)
            .map { $0 }
    }

    /// Tasks ordered high→low priority (stable within a priority), capped at `limit`.
    public static func topTasks(_ tasks: [LifeTask], limit: Int) -> [LifeTask] {
        func rank(_ p: TaskPriority) -> Int { p == .high ? 0 : (p == .medium ? 1 : 2) }
        return tasks
            .enumerated()
            .sorted { (rank($0.element.priority), $0.offset) < (rank($1.element.priority), $1.offset) }
            .map(\.element)
            .prefix(limit)
            .map { $0 }
    }
}
```

> If `TaskPriority` is nested in `LifeTask`, change the `rank` parameter type to `LifeTask.TaskPriority` and the comparisons accordingly. Match whatever the existing models declare.

- [ ] **Step 4: Run, expect PASS** — `swift test --filter LifeDashboardTests`, then full `swift test` (expect 41 + 3 = 44).

- [ ] **Step 5: Commit**
```bash
git add Sources/PRLifeKit/Model/LifeDashboard.swift Tests/PRLifeKitTests/LifeDashboardTests.swift
git commit -m "feat(kit): LifeDashboard nextEvents/topTasks selection helpers"
```

---

## Task 2: Shared Keychain access group

**Files:**
- Modify: `App/Net/KeychainConfig.swift`
- Modify: `App/PRLifeMobile.entitlements`
- Modify: `Widgets/PRLifeWidgets.entitlements`
- Modify: `project.yml`

- [ ] **Step 1: Add the access group to both entitlements files**

In `App/PRLifeMobile.entitlements` AND `Widgets/PRLifeWidgets.entitlements`, add inside the top-level `<dict>` (keep existing keys like the app-group):
```xml
  <key>keychain-access-groups</key>
  <array>
    <string>$(AppIdentifierPrefix)com.pramitranjan.prlife.shared</string>
  </array>
```

- [ ] **Step 2: Make `KeychainConfig` use the shared access group**

In `App/Net/KeychainConfig.swift`, add the access group constant and include it in every query dict. Add near `service`:
```swift
    private static let accessGroup = "8QBV8WL699.com.pramitranjan.prlife.shared"
```
Then in BOTH the `set(_:_:)` and `get(_:)` query dictionaries, add the access-group attribute alongside `kSecAttrService`:
```swift
                                kSecAttrAccessGroup as String: accessGroup,
```
(So each `q` dict has `kSecClass`, `kSecAttrService`, `kSecAttrAccount`, `kSecAttrAccessGroup`, plus the call-specific keys.)

- [ ] **Step 3: Give the widget target the config + a team for signing**

In `project.yml`, under the `PRLifeWidgets` target `sources:`, add the KeychainConfig file so the widget can read config:
```yaml
      - path: App/Net/KeychainConfig.swift
```
And under both `PRLifeMobile` and `PRLifeWidgets` `settings.base:` add (keychain sharing on device needs a team):
```yaml
        DEVELOPMENT_TEAM: 8QBV8WL699
```

- [ ] **Step 4: Build + install (entitlements must not break install)**
```bash
xcodegen generate
xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/v2t2 build | tail -6
APP=/tmp/v2t2/Build/Products/Debug-iphonesimulator/PRLifeMobile.app
xcrun simctl uninstall "iPhone 17 Pro" com.pramitranjan.prlife 2>/dev/null; true
xcrun simctl install "iPhone 17 Pro" "$APP" && echo "INSTALL OK"
```
Expected: `** BUILD SUCCEEDED **`, `INSTALL OK`. (If install fails on the keychain group, report the exact error — on the simulator keychain groups are normally permissive.)

- [ ] **Step 5: Commit**
```bash
git add App/Net/KeychainConfig.swift App/PRLifeMobile.entitlements Widgets/PRLifeWidgets.entitlements project.yml
git commit -m "feat: shared keychain access group so the widget reads API config"
```

---

## Task 3: Fonts + Theme available to the widget target

**Files:**
- Modify: `Widgets/Info.plist`
- Modify: `project.yml`

- [ ] **Step 1: Register fonts in the widget Info.plist**

Add to the top-level `<dict>` of `Widgets/Info.plist`:
```xml
  <key>UIAppFonts</key>
  <array>
    <string>ClashDisplay-Regular.otf</string>
    <string>ClashDisplay-Medium.otf</string>
    <string>ClashDisplay-Semibold.otf</string>
    <string>ClashDisplay-Bold.otf</string>
    <string>DMMono-Light.ttf</string>
    <string>DMMono-Regular.ttf</string>
    <string>DMMono-Medium.ttf</string>
  </array>
```
(Resources flatten to the bundle root — bare filenames, matching how the app target registers them.)

- [ ] **Step 2: Add fonts + Theme bridge to the widget target**

In `project.yml`, under the `PRLifeWidgets` target `sources:`, add:
```yaml
      - path: App/Theme/PRLifeTheme.swift
      - path: App/Resources/Fonts
```
(`PRLifeTheme.swift` only depends on SwiftUI + `PRLifeKit` `PRLifeTokens`, so it compiles in the widget target. The `Fonts` folder is bundled as resources.)

- [ ] **Step 3: Build + verify fonts land in the appex**
```bash
xcodegen generate
xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/v2t3 build | tail -5
ls /tmp/v2t3/Build/Products/Debug-iphonesimulator/PRLifeMobile.app/PlugIns/PRLifeWidgets.appex/ | grep -E "ClashDisplay|DMMono" | head
```
Expected: `** BUILD SUCCEEDED **` and the font files listed in the appex.

- [ ] **Step 4: Commit**
```bash
git add Widgets/Info.plist project.yml
git commit -m "feat: bundle fonts + theme bridge into the widget target"
```

---

## Task 4: Upcoming widget — provider + entry (direct-fetch)

**Files:**
- Create: `Widgets/UpcomingWidget.swift`

- [ ] **Step 1: Implement the timeline provider, entry, and widget config**

`Widgets/UpcomingWidget.swift`:
```swift
import WidgetKit
import SwiftUI
import PRLifeKit

enum UpcomingState { case ok, notConfigured, failed }

struct UpcomingEntry: TimelineEntry {
    let date: Date
    let events: [LifeEvent]
    let tasks: [LifeTask]
    let state: UpcomingState
}

struct UpcomingProvider: TimelineProvider {
    private func makeClient() -> LifeAPIClient {
        LifeAPIClient(configurationProvider: {
            let trimmed = KeychainConfig.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (URL(string: trimmed), KeychainConfig.token)
        })
    }

    func placeholder(in context: Context) -> UpcomingEntry {
        UpcomingEntry(date: .now, events: UpcomingSample.events, tasks: UpcomingSample.tasks, state: .ok)
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingEntry) -> Void) {
        completion(UpcomingEntry(date: .now, events: UpcomingSample.events, tasks: UpcomingSample.tasks, state: .ok))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingEntry>) -> Void) {
        let client = makeClient()
        Task {
            let next = Date().addingTimeInterval(30 * 60)
            do {
                async let e = client.fetchEvents(date: nil)
                async let t = client.fetchTasks()
                let entry = UpcomingEntry(date: .now, events: try await e, tasks: try await t, state: .ok)
                completion(Timeline(entries: [entry], policy: .after(next)))
            } catch LifeAPIError.notConfigured {
                completion(Timeline(entries: [UpcomingEntry(date: .now, events: [], tasks: [], state: .notConfigured)],
                                    policy: .after(next)))
            } catch {
                completion(Timeline(entries: [UpcomingEntry(date: .now, events: [], tasks: [], state: .failed)],
                                    policy: .after(next)))
            }
        }
    }
}

enum UpcomingSample {
    static let events = [
        LifeEvent(id: "1", title: "Review Session", start: Date().addingTimeInterval(1320), end: nil, calendarName: nil),
        LifeEvent(id: "2", title: "Studio Time", start: Date().addingTimeInterval(7200), end: nil, calendarName: nil),
    ]
    static let tasks = [
        LifeTask(id: "1", title: "Finish Albers brief", priority: .high, dueLocalDate: nil, projectSlug: "albers", status: "open"),
        LifeTask(id: "2", title: "Review gym log", priority: .medium, dueLocalDate: nil, projectSlug: "body", status: "open"),
    ]
}

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRLifeUpcoming", provider: UpcomingProvider()) { entry in
            UpcomingWidgetView(entry: entry)
        }
        .configurationDisplayName("Upcoming")
        .description("Your next events and due tasks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}
```

> Verify the real `LifeEvent`/`LifeTask` initializer signatures and `TaskPriority` location (Task 1 note) and adjust `UpcomingSample` accordingly so it compiles. `UpcomingWidgetView` is created in Task 5; this file won't compile until then — implement Task 5 before building.

- [ ] **Step 2: Commit (with Task 5; they form one buildable unit)** — proceed to Task 5, then build + commit together.

---

## Task 5: Upcoming widget — family views + register

**Files:**
- Create: `Widgets/UpcomingWidgetViews.swift`
- Modify: `Widgets/PRLifeWidgetsBundle.swift`

- [ ] **Step 1: Implement the family-switching views**

`Widgets/UpcomingWidgetViews.swift`:
```swift
import WidgetKit
import SwiftUI
import PRLifeKit

private func timeText(_ date: Date?) -> String {
    guard let date else { return "" }
    let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
}
private func priorityColor(_ p: TaskPriority) -> Color {
    switch p { case .high: return Theme.danger; case .medium: return Theme.amber; case .low: return Theme.label }
}

struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingEntry

    var body: some View {
        switch entry.state {
        case .notConfigured: setup
        case .failed where entry.events.isEmpty && entry.tasks.isEmpty: setup
        default: content
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PR LIFE").font(Theme.mono(10, .medium)).foregroundStyle(Theme.accent)
            Text("Set up in the app").font(Theme.mono(11)).foregroundStyle(Theme.label)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding()
    }

    @ViewBuilder private var content: some View {
        let nextEvents = LifeDashboard.nextEvents(entry.events, limit: family == .systemLarge ? 3 : 2)
        let tasks = LifeDashboard.topTasks(entry.tasks, limit: 3)
        switch family {
        case .accessoryInline:
            Text(nextEvents.first.map { "\(timeText($0.start)) \($0.title)" } ?? "No events")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("NEXT").font(.system(size: 10, weight: .medium))
                if let e = nextEvents.first {
                    Text(e.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(timeText(e.start)).font(.system(size: 12))
                } else { Text("No upcoming events").font(.system(size: 12)) }
            }
        case .systemSmall:
            small(nextEvents)
        case .systemMedium:
            medium(nextEvents, tasks)
        default:
            large(nextEvents, tasks)
        }
    }

    private func small(_ events: [LifeEvent]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("NEXT_").font(Theme.mono(10)).foregroundStyle(Theme.label)
            if let e = events.first {
                Text(e.title).font(Theme.display(15)).foregroundStyle(Theme.text).lineLimit(2)
                Text(timeText(e.start)).font(Theme.mono(11)).foregroundStyle(Theme.accent)
            } else { Text("Clear").font(Theme.display(15)).foregroundStyle(Theme.text) }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(14)
    }

    private func medium(_ events: [LifeEvent], _ tasks: [LifeTask]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Text("UPCOMING_").font(Theme.mono(10)).foregroundStyle(Theme.label)
                ForEach(events) { e in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.title).font(Theme.body(12)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(timeText(e.start)).font(Theme.mono(10)).foregroundStyle(Theme.accent)
                    }
                }
                Spacer()
            }
            Divider().overlay(Theme.hairline)
            VStack(alignment: .leading, spacing: 7) {
                Text("DUE_").font(Theme.mono(10)).foregroundStyle(Theme.label)
                ForEach(tasks) { t in
                    HStack(spacing: 6) {
                        Circle().fill(priorityColor(t.priority)).frame(width: 5, height: 5)
                        Text(t.title).font(Theme.body(12)).foregroundStyle(Theme.text).lineLimit(1)
                    }
                }
                Spacer()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(14)
    }

    private func large(_ events: [LifeEvent], _ tasks: [LifeTask]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EVENTS_").font(Theme.mono(10)).foregroundStyle(Theme.label)
            ForEach(events) { e in
                HStack(spacing: 8) {
                    Text(timeText(e.start)).font(Theme.mono(10)).foregroundStyle(Theme.accent).frame(width: 40, alignment: .leading)
                    Text(e.title).font(Theme.body(13)).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Text("DUE TODAY_").font(Theme.mono(10)).foregroundStyle(Theme.label)
            ForEach(tasks) { t in
                HStack(spacing: 8) {
                    Circle().fill(priorityColor(t.priority)).frame(width: 6, height: 6)
                    Text(t.title).font(Theme.body(13)).foregroundStyle(Theme.text).lineLimit(1)
                }
            }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(16)
    }
}
```

> Adjust `priorityColor`'s parameter type if `TaskPriority` is nested (`LifeTask.TaskPriority`). `Theme` + `Color(hex:)` come from the `PRLifeTheme.swift` now in the widget target (Task 3).

- [ ] **Step 2: Register the widget in the bundle**

`Widgets/PRLifeWidgetsBundle.swift` — add `UpcomingWidget()`:
```swift
import WidgetKit
import SwiftUI

@main
struct PRLifeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UpcomingWidget()
        QuickCaptureWidget()
        RecordingLiveActivity()
    }
}
```

- [ ] **Step 3: Build + install + add the widget in the simulator**
```bash
xcodegen generate
xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/v2t5 build | tail -6
APP=/tmp/v2t5/Build/Products/Debug-iphonesimulator/PRLifeMobile.app
xcrun simctl uninstall "iPhone 17 Pro" com.pramitranjan.prlife 2>/dev/null; true
xcrun simctl install "iPhone 17 Pro" "$APP" && echo INSTALL OK
```
Expected: `** BUILD SUCCEEDED **`, `INSTALL OK`. Then manually add the "Upcoming" widget (small/medium/large) on the simulator home screen and screenshot — it should render sample/placeholder data with correct fonts + theme. (Live data requires a configured token; widget shows the "Set up in the app" state until then.)

- [ ] **Step 4: Commit**
```bash
git add Widgets/UpcomingWidget.swift Widgets/UpcomingWidgetViews.swift Widgets/PRLifeWidgetsBundle.swift
git commit -m "feat: iOS Upcoming widget (events + tasks) for home + lock-screen families"
```

---

## Task 6: Reload widgets after a capture upload

**Files:**
- Modify: `App/CaptureEnvironment.swift`

- [ ] **Step 1: Reload timelines when capture state changes**

In `App/CaptureEnvironment.swift`, find where a capture finishes uploading / `publishCaptureStateChange()` is called. Add a WidgetKit reload so a fresh capture nudges the widget. Add `import WidgetKit` at the top, and in `publishCaptureStateChange()` (or right after the upload completes in the router `stop` closure) add:
```swift
        WidgetCenter.shared.reloadTimelines(ofKind: "PRLifeUpcoming")
```
(If `publishCaptureStateChange()` already posts a notification, place the reload there so all surfaces refresh consistently.)

- [ ] **Step 2: Build**
```bash
xcodegen generate
xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**
```bash
git add App/CaptureEnvironment.swift
git commit -m "feat: reload Upcoming widget timeline after capture"
```

---

## Task 7: Final verification

- [ ] **Step 1: Full kit suite** — `swift test` (expect 44, all pass).
- [ ] **Step 2: App build** — `xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build | tail -5` → BUILD SUCCEEDED.
- [ ] **Step 3: Install + screenshots** — install, add small/medium/large Upcoming widgets + the lock-screen accessory; screenshot each; confirm layout matches the handoff specs (square corners, DM Mono/Clash, priority dots).
- [ ] **Step 4: Device-QA note** — record that live widget data + 30-min refresh + lock-screen accessory must be validated on a physical device with a configured `LIFE_MOBILE_TOKEN` (widget networking + shared Keychain can't be exercised in unit tests). Append results to `docs/v1-device-qa-checklist.md` or a new v2 note.
- [ ] **Step 5: Commit any screenshot notes** if added.

---

## Self-Review
- **Spec coverage:** widgets-only (home S/M/L + lock accessory) → Tasks 4–5; direct-fetch via shared Keychain → Tasks 2, 4; selection helpers → Task 1; fonts/theme → Task 3; reload nudge → Task 6; testing → Tasks 1 + 7. LifeEvent/LifeTask/fetch already exist (noted). ✓
- **Placeholder scan:** none — all steps have concrete code/commands. The "verify init signatures" notes are real safeguards (the models were written by Codex; confirm shapes), not deferrals. ✓
- **Type consistency:** `UpcomingEntry`, `UpcomingProvider`, `UpcomingWidget`, `UpcomingWidgetView`, `LifeDashboard.nextEvents/topTasks`, `priorityColor`, kind `"PRLifeUpcoming"` used consistently across tasks. ✓
- **Risk flagged:** `TaskPriority` nesting + `LifeEvent`/`LifeTask` init signatures must be confirmed against Codex's actual models before Tasks 1/4/5 compile — called out inline in each.
```
