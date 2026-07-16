# PR Life macOS Companion App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the PR Life macOS companion — a menu-bar-first quiet utility showing today's events/tasks, with desktop-mic Quick Capture, global hotkeys, and WidgetKit widgets — as a new `PRLifeMac` target in the existing monorepo, reusing `PRLifeKit`.

**Architecture:** Platform-free logic (models, API reads, snapshot cache, hotkey bindings) lands in `PRLifeKit` under strict TDD via `swift test`. macOS-only concretes (mic, transcription, Carbon hotkeys, MenuBarExtra, windows, widgets) live in the `PRLifeMac` app target / `PRLifeMacWidgets` extension and are verified by `xcodebuild` + manual QA (runtime/permission/visual gates). The app fetches data and writes a shared `LifeSnapshot` JSON into the App Group container; widgets read that snapshot and never hit the network.

**Tech Stack:** Swift 5.9 mode (Xcode 26.5), SwiftUI, `MenuBarExtra`, WidgetKit (macOS 14), AVFoundation (`AVAudioRecorder`), Speech framework, Carbon `RegisterEventHotKey`, SwiftData, XcodeGen, XCTest.

**Spec:** `docs/specs/2026-06-20-pr-life-macos-companion-app-design.md`

**Conventions:**
- Reuse `PRLifeKit` wholesale; re-add Theme/fonts/AppGroup in the macOS target; **share** `KeychainConfig` source across targets.
- Treat SourceKit "No such module 'PRLifeKit'" / cross-file diagnostics as false positives when `swift test` / `xcodebuild` pass.
- End every commit message with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Greenfield work stays on `main` locally. Never push. Do not touch `~/portfolio`.
- After any `project.yml` change, run `xcodegen generate`.

**Build/test commands:**
- Kit tests: `cd ~/Developer/PRLifeMobile && swift test`
- App build: `cd ~/Developer/PRLifeMobile && xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build`

---

## Phase 1 — `PRLifeKit` net-new (platform-free, strict TDD)

### Task 1: `LifeEvent` model

**Files:**
- Create: `Sources/PRLifeKit/Model/LifeEvent.swift`
- Test: `Tests/PRLifeKitTests/LifeEventTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PRLifeKit

final class LifeEventTests: XCTestCase {
    func test_decodesCalendarRow_withSnakeCaseAndNulls() throws {
        let json = #"""
        {
          "id": "evt_1",
          "title": "Review Session",
          "start_time": "2026-06-20T14:00:00+00:00",
          "end_time": "2026-06-20T15:30:00+00:00",
          "all_day": false,
          "location": "Studio",
          "local_date": "2026-06-20"
        }
        """#.data(using: .utf8)!

        let event = try JSONDecoder().decode(LifeEvent.self, from: json)

        XCTAssertEqual(event.id, "evt_1")
        XCTAssertEqual(event.title, "Review Session")
        XCTAssertEqual(event.allDay, false)
        XCTAssertEqual(event.location, "Studio")
        XCTAssertEqual(event.localDate, "2026-06-20")
        XCTAssertNotNil(event.start)
        XCTAssertNotNil(event.end)
    }

    func test_decodesAllDayEvent_withNullTitleAndTimes() throws {
        let json = #"""
        { "id": "evt_2", "title": null, "start_time": null, "end_time": null,
          "all_day": true, "location": null, "local_date": "2026-06-20" }
        """#.data(using: .utf8)!

        let event = try JSONDecoder().decode(LifeEvent.self, from: json)

        XCTAssertNil(event.title)
        XCTAssertNil(event.start)
        XCTAssertTrue(event.allDay)
    }

    func test_parsesFractionalSecondsTimestamp() throws {
        let json = #"""
        { "id": "evt_3", "title": "Gym", "start_time": "2026-06-20T19:00:00.000Z",
          "end_time": null, "all_day": false, "location": null, "local_date": "2026-06-20" }
        """#.data(using: .utf8)!

        let event = try JSONDecoder().decode(LifeEvent.self, from: json)
        XCTAssertNotNil(event.start)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LifeEventTests`
Expected: FAIL — `cannot find 'LifeEvent' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A calendar event read from `GET /api/life/calendar`. `startTime`/`endTime` are kept
/// as raw ISO8601 strings (trivial Codable) with parsed `Date` exposed via `start`/`end`.
public struct LifeEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String?
    public let startTime: String?
    public let endTime: String?
    public let allDay: Bool
    public let location: String?
    public let localDate: String

    enum CodingKeys: String, CodingKey {
        case id, title, location
        case startTime = "start_time"
        case endTime = "end_time"
        case allDay = "all_day"
        case localDate = "local_date"
    }

    public init(id: String, title: String?, startTime: String?, endTime: String?,
                allDay: Bool, location: String?, localDate: String) {
        self.id = id; self.title = title; self.startTime = startTime; self.endTime = endTime
        self.allDay = allDay; self.location = location; self.localDate = localDate
    }

    public var start: Date? { LifeEvent.parseISO(startTime) }
    public var end: Date? { LifeEvent.parseISO(endTime) }

    /// Tolerant of both plain and fractional-second internet timestamps.
    static func parseISO(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LifeEventTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PRLifeKit/Model/LifeEvent.swift Tests/PRLifeKitTests/LifeEventTests.swift
git commit -m "feat(kit): add LifeEvent model with tolerant ISO8601 parsing

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `LifeTask` model

**Files:**
- Create: `Sources/PRLifeKit/Model/LifeTask.swift`
- Test: `Tests/PRLifeKitTests/LifeTaskTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PRLifeKit

final class LifeTaskTests: XCTestCase {
    func test_decodesTaskRow() throws {
        let json = #"""
        { "id": "t1", "title": "Finish Albers brief", "priority": "high",
          "due_local_date": "2026-06-20", "project_slug": "albers", "status": "open" }
        """#.data(using: .utf8)!

        let task = try JSONDecoder().decode(LifeTask.self, from: json)

        XCTAssertEqual(task.id, "t1")
        XCTAssertEqual(task.title, "Finish Albers brief")
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.dueLocalDate, "2026-06-20")
        XCTAssertEqual(task.projectSlug, "albers")
        XCTAssertEqual(task.status, "open")
    }

    func test_unknownPriorityDefaultsToMedium() throws {
        let json = #"""
        { "id": "t2", "title": "x", "priority": "urgent",
          "due_local_date": null, "project_slug": null, "status": "open" }
        """#.data(using: .utf8)!
        let task = try JSONDecoder().decode(LifeTask.self, from: json)
        XCTAssertEqual(task.priority, .medium)
        XCTAssertNil(task.dueLocalDate)
    }

    func test_isDueOn_matchesLocalDate() {
        let task = LifeTask(id: "t3", title: "y", priority: .low,
                            dueLocalDate: "2026-06-20", projectSlug: nil, status: "open")
        XCTAssertTrue(task.isDue(on: "2026-06-20"))
        XCTAssertFalse(task.isDue(on: "2026-06-21"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LifeTaskTests`
Expected: FAIL — `cannot find 'LifeTask' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum LifeTaskPriority: String, Codable, Sendable, CaseIterable {
    case high, medium, low
}

/// A task read from `GET /api/life/tasks`.
public struct LifeTask: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let priority: LifeTaskPriority
    public let dueLocalDate: String?
    public let projectSlug: String?
    public let status: String

    enum CodingKeys: String, CodingKey {
        case id, title, priority, status
        case dueLocalDate = "due_local_date"
        case projectSlug = "project_slug"
    }

    public init(id: String, title: String, priority: LifeTaskPriority,
                dueLocalDate: String?, projectSlug: String?, status: String) {
        self.id = id; self.title = title; self.priority = priority
        self.dueLocalDate = dueLocalDate; self.projectSlug = projectSlug; self.status = status
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        let raw = try c.decodeIfPresent(String.self, forKey: .priority)
        priority = raw.flatMap(LifeTaskPriority.init(rawValue:)) ?? .medium
        dueLocalDate = try c.decodeIfPresent(String.self, forKey: .dueLocalDate)
        projectSlug = try c.decodeIfPresent(String.self, forKey: .projectSlug)
        status = try c.decode(String.self, forKey: .status)
    }

    public func isDue(on localDate: String) -> Bool { dueLocalDate == localDate }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LifeTaskTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PRLifeKit/Model/LifeTask.swift Tests/PRLifeKitTests/LifeTaskTests.swift
git commit -m "feat(kit): add LifeTask model with priority fallback

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `LifeAPIClient.fetchEvents` + `fetchTasks`

**Files:**
- Modify: `Sources/PRLifeKit/API/LifeAPIClient.swift`
- Test: `Tests/PRLifeKitTests/LifeAPIReadsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PRLifeKit

final class LifeAPIReadsTests: XCTestCase {
    private func makeClient() -> LifeAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return LifeAPIClient(baseURL: URL(string: "https://example.com")!,
                             token: "secret-token", session: session)
    }

    func test_fetchEvents_buildsAuthorizedGet_andDecodes() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertEqual(req.url?.absoluteString,
                           "https://example.com/api/life/calendar?date=2026-06-20")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"""
            {"localDate":"2026-06-20","timezone":"Asia/Kuala_Lumpur","events":[
              {"id":"e1","title":"Review","start_time":"2026-06-20T14:00:00+00:00",
               "end_time":null,"all_day":false,"location":null,"local_date":"2026-06-20"}]}
            """#.data(using: .utf8)!
            return (resp, body)
        }
        let events = try await makeClient().fetchEvents(date: "2026-06-20")
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, "e1")
    }

    func test_fetchTasks_usesActiveStatus_andDecodes() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "GET")
            XCTAssertEqual(req.url?.absoluteString,
                           "https://example.com/api/life/tasks?status=active")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"""
            {"tasks":[{"id":"t1","title":"Albers","priority":"high",
              "due_local_date":"2026-06-20","project_slug":"albers","status":"open"}]}
            """#.data(using: .utf8)!
            return (resp, body)
        }
        let tasks = try await makeClient().fetchTasks()
        XCTAssertEqual(tasks.first?.priority, .high)
    }

    func test_fetchEvents_throwsNotConfigured_whenPlaceholder() async {
        let client = LifeAPIClient(configurationProvider: { (nil, nil) })
        do { _ = try await client.fetchEvents(date: nil); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? LifeAPIError, .notConfigured) }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LifeAPIReadsTests`
Expected: FAIL — `value of type 'LifeAPIClient' has no member 'fetchEvents'`.

- [ ] **Step 3: Write minimal implementation** (append to `LifeAPIClient`)

```swift
    private struct EventsResponse: Decodable { let events: [LifeEvent] }
    private struct TasksResponse: Decodable { let tasks: [LifeTask] }

    /// Resolves config and rejects empty token / placeholder host. Returns trimmed token.
    private func validConfiguration() throws -> (URL, String) {
        let (base, token) = resolvedConfiguration()
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaceholder = base.host(percentEncoded: false) == "prlife.invalid"
        guard !trimmed.isEmpty, !isPlaceholder else { throw LifeAPIError.notConfigured }
        return (base, trimmed)
    }

    private func authorizedGET(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func validate(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw LifeAPIError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw LifeAPIError.server(status: http.statusCode,
                                      body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Reads `GET /api/life/calendar`. `date` (YYYY-MM-DD) is optional; when nil the
    /// server uses the owner's timezone default.
    public func fetchEvents(date: String?) async throws -> [LifeEvent] {
        let (base, token) = try validConfiguration()
        var comps = URLComponents(
            url: base.appendingPathComponent("api/life/calendar"),
            resolvingAgainstBaseURL: false)!
        if let date { comps.queryItems = [URLQueryItem(name: "date", value: date)] }
        let (data, response) = try await session.data(for: authorizedGET(comps.url!, token: token))
        try validate(data, response)
        guard let decoded = try? JSONDecoder().decode(EventsResponse.self, from: data) else {
            throw LifeAPIError.decoding
        }
        return decoded.events
    }

    /// Reads active tasks from `GET /api/life/tasks?status=active`.
    public func fetchTasks() async throws -> [LifeTask] {
        let (base, token) = try validConfiguration()
        var comps = URLComponents(
            url: base.appendingPathComponent("api/life/tasks"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "status", value: "active")]
        let (data, response) = try await session.data(for: authorizedGET(comps.url!, token: token))
        try validate(data, response)
        guard let decoded = try? JSONDecoder().decode(TasksResponse.self, from: data) else {
            throw LifeAPIError.decoding
        }
        return decoded.tasks
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LifeAPIReadsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Run full kit suite (no regressions)**

Run: `swift test`
Expected: PASS (existing 28 + new tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/PRLifeKit/API/LifeAPIClient.swift Tests/PRLifeKitTests/LifeAPIReadsTests.swift
git commit -m "feat(kit): add fetchEvents/fetchTasks reads to LifeAPIClient

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `LifeSnapshot` + `FileLifeSnapshotStore`

**Files:**
- Create: `Sources/PRLifeKit/Cache/LifeSnapshot.swift`
- Create: `Sources/PRLifeKit/Cache/LifeSnapshotStore.swift`
- Test: `Tests/PRLifeKitTests/LifeSnapshotStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PRLifeKit

final class LifeSnapshotStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("snap-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func test_load_returnsNil_whenNoFile() {
        let store = FileLifeSnapshotStore(directory: tempDir())
        XCTAssertNil(store.load())
    }

    func test_saveThenLoad_roundTrips() throws {
        let dir = tempDir()
        let store = FileLifeSnapshotStore(directory: dir)
        let event = LifeEvent(id: "e1", title: "Review", startTime: "2026-06-20T14:00:00+00:00",
                              endTime: nil, allDay: false, location: nil, localDate: "2026-06-20")
        let task = LifeTask(id: "t1", title: "Albers", priority: .high,
                            dueLocalDate: "2026-06-20", projectSlug: "albers", status: "open")
        let snapshot = LifeSnapshot(events: [event], tasks: [task],
                                    lastSync: Date(timeIntervalSince1970: 1_750_000_000))

        try store.save(snapshot)
        let loaded = store.load()

        XCTAssertEqual(loaded, snapshot)
        XCTAssertEqual(loaded?.events.first?.id, "e1")
        XCTAssertEqual(loaded?.tasks.first?.priority, .high)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LifeSnapshotStoreTests`
Expected: FAIL — `cannot find 'FileLifeSnapshotStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Cache/LifeSnapshot.swift`:

```swift
import Foundation

/// The single cached payload both the app and widget read.
public struct LifeSnapshot: Codable, Equatable, Sendable {
    public let events: [LifeEvent]
    public let tasks: [LifeTask]
    public let lastSync: Date

    public init(events: [LifeEvent], tasks: [LifeTask], lastSync: Date) {
        self.events = events; self.tasks = tasks; self.lastSync = lastSync
    }
}
```

`Cache/LifeSnapshotStore.swift`:

```swift
import Foundation

public protocol LifeSnapshotStoring: Sendable {
    func load() -> LifeSnapshot?
    func save(_ snapshot: LifeSnapshot) throws
}

/// Persists the snapshot as JSON. In the app it is constructed with the App Group
/// container directory so the widget extension reads the same file.
public final class FileLifeSnapshotStore: LifeSnapshotStoring {
    private let url: URL

    public init(directory: URL, fileName: String = "life-snapshot.json") {
        self.url = directory.appendingPathComponent(fileName)
    }

    public func load() -> LifeSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LifeSnapshot.self, from: data)
    }

    public func save(_ snapshot: LifeSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LifeSnapshotStoreTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PRLifeKit/Cache Tests/PRLifeKitTests/LifeSnapshotStoreTests.swift
git commit -m "feat(kit): add LifeSnapshot + file-backed snapshot store

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Global hotkey bindings (kit-side, platform-free)

**Files:**
- Create: `Sources/PRLifeKit/Capture/GlobalHotKey.swift`
- Test: `Tests/PRLifeKitTests/GlobalHotKeyTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PRLifeKit

final class GlobalHotKeyTests: XCTestCase {
    func test_defaultBindings_coverAllContexts_withCtrlOpt() {
        let bindings = HotKeyBinding.defaults
        XCTAssertEqual(bindings.count, 4)
        XCTAssertEqual(Set(bindings.map(\.context)),
                       Set([.quick, .work, .journal, .ideas]))
        // Control(0x1000) + Option(0x0800) on every chord.
        for binding in bindings {
            XCTAssertEqual(binding.modifiers, 0x1000 | 0x0800)
        }
    }

    func test_defaultBindings_useExpectedKeyCodes() {
        let byContext = Dictionary(uniqueKeysWithValues: HotKeyBinding.defaults.map { ($0.context, $0.keyCode) })
        XCTAssertEqual(byContext[.quick], 49)   // Space
        XCTAssertEqual(byContext[.work], 13)    // W
        XCTAssertEqual(byContext[.journal], 38) // J
        XCTAssertEqual(byContext[.ideas], 34)   // I
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GlobalHotKeyTests`
Expected: FAIL — `cannot find 'HotKeyBinding' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// A global hotkey chord mapped to a capture context. `keyCode`/`modifiers` are raw
/// Carbon values so the macOS concrete can register them directly; defined here
/// (platform-free) so they are unit-testable and shared.
public struct HotKeyBinding: Equatable, Sendable {
    public let context: CaptureContext
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(context: CaptureContext, keyCode: UInt32, modifiers: UInt32) {
        self.context = context; self.keyCode = keyCode; self.modifiers = modifiers
    }

    /// Carbon `controlKey | optionKey`.
    public static let ctrlOption: UInt32 = 0x1000 | 0x0800

    /// ⌃⌥Space / ⌃⌥W / ⌃⌥J / ⌃⌥I — matches the Devices-tab spec.
    public static let defaults: [HotKeyBinding] = [
        HotKeyBinding(context: .quick,   keyCode: 49, modifiers: ctrlOption), // Space
        HotKeyBinding(context: .work,    keyCode: 13, modifiers: ctrlOption), // W
        HotKeyBinding(context: .journal, keyCode: 38, modifiers: ctrlOption), // J
        HotKeyBinding(context: .ideas,   keyCode: 34, modifiers: ctrlOption), // I
    ]
}

/// Registers global hotkeys. The macOS concrete wraps Carbon `RegisterEventHotKey`;
/// tests use a fake. `onTrigger` is called on the main actor by the concrete.
public protocol GlobalHotKeyRegistering: AnyObject {
    func register(_ bindings: [HotKeyBinding], onTrigger: @escaping (CaptureContext) -> Void)
    func unregisterAll()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GlobalHotKeyTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Run full kit suite**

Run: `swift test`
Expected: PASS (all).

- [ ] **Step 6: Commit**

```bash
git add Sources/PRLifeKit/Capture/GlobalHotKey.swift Tests/PRLifeKitTests/GlobalHotKeyTests.swift
git commit -m "feat(kit): add global hotkey bindings + registrar protocol

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 2 — macOS app target scaffold

### Task 6: Add `PRLifeMac` target + minimal app builds

**Files:**
- Modify: `project.yml`
- Create: `MacApp/PRLifeMacApp.swift`
- Create: `MacApp/Resources/Info.plist`
- Create: `MacApp/PRLifeMac.entitlements`
- Create: `MacApp/AppGroup.swift`

- [ ] **Step 1: Add macOS deployment target + targets to `project.yml`**

Under `options.deploymentTarget`, add `macOS: "14.0"`. Append these targets (keep existing iOS targets unchanged):

```yaml
  PRLifeMac:
    type: application
    platform: macOS
    sources:
      - MacApp
    dependencies:
      - package: PRLifeKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.pramitranjan.prlife.mac
        INFOPLIST_FILE: MacApp/Resources/Info.plist
        SWIFT_VERSION: "5.9"
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_STYLE: Automatic
        CODE_SIGN_ENTITLEMENTS: MacApp/PRLifeMac.entitlements
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        ENABLE_HARDENED_RUNTIME: YES
```

Add a scheme:

```yaml
  PRLifeMac:
    build:
      targets:
        PRLifeMac: all
    run:
      config: Debug
```

- [ ] **Step 2: Create `MacApp/Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PR Life</string>
  <key>CFBundleDisplayName</key><string>PR Life</string>
  <key>CFBundleIdentifier</key><string>com.pramitranjan.prlife.mac</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>PR Life records voice captures from your desktop microphone.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>PR Life transcribes your voice captures on-device before uploading.</string>
</dict>
</plist>
```

- [ ] **Step 3: Create `MacApp/PRLifeMac.entitlements`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key><true/>
  <key>com.apple.security.device.audio-input</key><true/>
  <key>com.apple.security.network.client</key><true/>
  <key>com.apple.security.application-groups</key>
  <array><string>group.com.pramitranjan.prlife</string></array>
</dict>
</plist>
```

- [ ] **Step 4: Create `MacApp/AppGroup.swift`**

```swift
import Foundation

enum AppGroup {
    static let id = "group.com.pramitranjan.prlife"

    /// Shared container directory; falls back to Application Support if unavailable.
    static var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}
```

- [ ] **Step 5: Create `MacApp/PRLifeMacApp.swift` (placeholder MenuBarExtra)**

```swift
import SwiftUI

@main
struct PRLifeMacApp: App {
    var body: some Scene {
        MenuBarExtra("PR Life", systemImage: "waveform") {
            Text("PR Life_")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 6: Regenerate + build**

Run:
```bash
cd ~/Developer/PRLifeMobile && xcodegen generate && xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add project.yml MacApp
git commit -m "feat(mac): scaffold PRLifeMac target with MenuBarExtra shell

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**Manual QA (flag):** Run the app from Xcode; confirm a menu-bar icon appears and the popover opens with "PR Life_". No Dock icon (LSUIElement).

---

### Task 7: Re-add Theme bridge + fonts in the macOS target

**Files:**
- Create: `MacApp/Theme/PRLifeTheme.swift` (copy the iOS `App/Theme/PRLifeTheme.swift` pattern: `Color(hex:)` + `Theme` enum over `PRLifeTokens`, `Theme.mono/display/body`)
- Create: `MacApp/Resources/Fonts/` — copy the four font files from `App/Resources/Fonts/` (`ClashDisplay-{Regular,Medium,Semibold,Bold}.otf`, `DMMono-{Light,Regular,Medium}.ttf`)
- Modify: `MacApp/Resources/Info.plist` (register `ATSApplicationFontsPath`)
- Modify: `project.yml` (ensure `MacApp` sources include `Resources/Fonts`)

- [ ] **Step 1: Copy fonts**

Run:
```bash
cd ~/Developer/PRLifeMobile && mkdir -p MacApp/Resources/Fonts && cp App/Resources/Fonts/* MacApp/Resources/Fonts/
```

- [ ] **Step 2: Copy + adapt the Theme bridge**

Copy `App/Theme/PRLifeTheme.swift` to `MacApp/Theme/PRLifeTheme.swift` verbatim (it uses cross-platform SwiftUI `Color`/`Font` over `PRLifeTokens`). If it references any UIKit type, replace with the SwiftUI equivalent. Register fonts at launch via `Font.custom` (no UIKit registration needed when bundled + listed in Info.plist).

- [ ] **Step 3: Register fonts in Info.plist** — add inside the top-level `<dict>`:

```xml
  <key>ATSApplicationFontsPath</key><string>Fonts</string>
```

- [ ] **Step 4: Verify the bridge renders** — temporarily set the placeholder text to `Theme.display(22)`:

```swift
Text("PR Life_").font(Theme.display(22)).foregroundStyle(Theme.text)
```

- [ ] **Step 5: Regenerate + build**

Run: `cd ~/Developer/PRLifeMobile && xcodegen generate && xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add MacApp/Theme MacApp/Resources/Fonts project.yml MacApp/Resources/Info.plist
git commit -m "feat(mac): re-add Theme bridge and fonts to macOS target

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**Manual QA (flag):** Run; confirm the placeholder renders in Clash Display, not the system font.

---

## Phase 3 — macOS capture concretes + environment

### Task 8: Share `KeychainConfig`; add macOS reachability

**Files:**
- Modify: `project.yml` (add `App/Net/KeychainConfig.swift` as a shared source path to `MacApp` target)
- Create: `MacApp/Net/PathMonitorReachability.swift`
- Create: `MacApp/Resources/LocalAPIConfig.plist` (optional dev defaults; may be empty `<dict/>`)

- [ ] **Step 1: Share KeychainConfig** — in `project.yml`, give the `MacApp` target an explicit `sources` list that adds the shared file:

```yaml
    sources:
      - MacApp
      - path: App/Net/KeychainConfig.swift
```
(`KeychainConfig` reads `LocalAPIConfig` from `Bundle.main`; the macOS bundle provides its own copy in Step 3.)

- [ ] **Step 2: Add macOS reachability** (`NWPathMonitor`, implementing `ReachabilityProviding`):

```swift
import Foundation
import Network
import PRLifeKit

/// Network reachability for macOS via NWPathMonitor.
final class PathMonitorReachability: ReachabilityProviding, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "prlife.pathmonitor")
    private let lock = NSLock()
    private var status: ConnectivityStatus = .offline

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let next: ConnectivityStatus
            if path.status != .satisfied { next = .offline }
            else if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) { next = .wifi }
            else { next = .cellular }
            self.lock.lock(); self.status = next; self.lock.unlock()
        }
        monitor.start(queue: queue)
    }

    func current() -> ConnectivityStatus {
        lock.lock(); defer { lock.unlock() }
        return status
    }
}
```

- [ ] **Step 3: Create `MacApp/Resources/LocalAPIConfig.plist`** with `<dict/>` (empty; real values entered in Settings at runtime). Ensure it is bundled (under `MacApp/Resources`, already in sources).

- [ ] **Step 4: Regenerate + build**

Run: `cd ~/Developer/PRLifeMobile && xcodegen generate && xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add project.yml MacApp/Net MacApp/Resources/LocalAPIConfig.plist
git commit -m "feat(mac): share KeychainConfig and add NWPathMonitor reachability

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: macOS audio recorder concrete

**Files:**
- Create: `MacApp/Capture/MacAudioRecorderService.swift`

- [ ] **Step 1: Implement `AudioRecording` for macOS** (no `AVAudioSession`; permission via `AVCaptureDevice`):

```swift
import Foundation
import AVFoundation
import PRLifeKit

/// macOS desktop-mic recorder. Unlike iOS there is no AVAudioSession; AVAudioRecorder
/// records directly. Mic permission is requested via AVCaptureDevice.
final class MacAudioRecorderService: NSObject, AudioRecording, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private(set) var isRecording = false

    static var capturesDir: URL {
        let dir = AppGroup.containerURL.appendingPathComponent("captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start() async throws -> String {
        let granted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .audio)
        default: granted = false
        }
        guard granted else { throw RecordingError.permissionDenied }

        let name = "capture-\(UUID().uuidString).m4a"
        let url = Self.capturesDir.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.prepareToRecord()
            guard rec.record() else { throw RecordingError.sessionFailed("Recording could not start.") }
            recorder = rec
            isRecording = rec.isRecording
            return name
        } catch let error as RecordingError {
            throw error
        } catch {
            throw RecordingError.sessionFailed("\(error)")
        }
    }

    func stop() async -> TimeInterval {
        let d = recorder?.currentTime ?? 0
        recorder?.stop(); recorder = nil; isRecording = false
        return d
    }
}
```

- [ ] **Step 2: Build**

Run: `cd ~/Developer/PRLifeMobile && xcodegen generate && xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MacApp/Capture/MacAudioRecorderService.swift
git commit -m "feat(mac): add desktop-mic AudioRecording concrete

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**Manual QA (flag, deferred to Task 13):** mic permission prompt + actual recording verified once the coordinator is wired.

---

### Task 10: macOS transcriber concrete

**Files:**
- Create: `MacApp/Capture/SpeechTranscriber.swift`

- [ ] **Step 1: Port the iOS `SpeechTranscriber`** verbatim from `App/Capture/SpeechTranscriber.swift`, changing only the captures-dir reference from `AVAudioRecorderService.capturesDir` to `MacAudioRecorderService.capturesDir`. Keep the `ResumeBox`, on-device requirement, 60s watchdog, locale selection, and error mapping unchanged.

- [ ] **Step 2: Build**

Run: `cd ~/Developer/PRLifeMobile && xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MacApp/Capture/SpeechTranscriber.swift
git commit -m "feat(mac): add on-device Speech transcriber concrete

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 11: macOS SwiftData capture store

**Files:**
- Create: `MacApp/Capture/SwiftDataCaptureStore.swift`

- [ ] **Step 1: Port the iOS store + entity** from `App/Capture/SwiftDataCaptureStore.swift` verbatim (the `CaptureEntity` `@Model` + `SwiftDataCaptureStore: CaptureStoring`). It is platform-free SwiftData; no changes needed beyond living in the macOS target.

- [ ] **Step 2: Build**

Run: `cd ~/Developer/PRLifeMobile && xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MacApp/Capture/SwiftDataCaptureStore.swift
git commit -m "feat(mac): add SwiftData capture store

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 12: Carbon global hotkey concrete

**Files:**
- Create: `MacApp/Capture/CarbonHotKeyManager.swift`

- [ ] **Step 1: Implement `GlobalHotKeyRegistering` via Carbon**:

```swift
import Foundation
import Carbon.HIToolbox
import PRLifeKit

/// Registers system-wide hotkeys using Carbon RegisterEventHotKey. Each chord fires
/// `onTrigger` with its CaptureContext on the main actor. No Accessibility permission needed.
final class CarbonHotKeyManager: GlobalHotKeyRegistering {
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var contextByID: [UInt32: CaptureContext] = [:]
    private var onTrigger: ((CaptureContext) -> Void)?
    private var handler: EventHandlerRef?
    private let signature: OSType = 0x50524C46 // 'PRLF'

    func register(_ bindings: [HotKeyBinding], onTrigger: @escaping (CaptureContext) -> Void) {
        unregisterAll()
        self.onTrigger = onTrigger

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let manager = Unmanaged<CarbonHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            if let context = manager.contextByID[hkID.id] {
                DispatchQueue.main.async { manager.onTrigger?(context) }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        for (index, binding) in bindings.enumerated() {
            let id = UInt32(index + 1)
            contextByID[id] = binding.context
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: signature, id: id)
            RegisterEventHotKey(binding.keyCode, binding.modifiers, hkID,
                                GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }
    }

    func unregisterAll() {
        for ref in hotKeyRefs where ref != nil { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        contextByID.removeAll()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }

    deinit { unregisterAll() }
}
```

- [ ] **Step 2: Build**

Run: `cd ~/Developer/PRLifeMobile && xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MacApp/Capture/CarbonHotKeyManager.swift
git commit -m "feat(mac): add Carbon global hotkey manager

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**Manual QA (flag, deferred to Task 13):** chords trigger capture once wired.

---

### Task 13: `MacCaptureEnvironment` — wire the capture stack

**Files:**
- Create: `MacApp/MacCaptureEnvironment.swift`
- Modify: `MacApp/PRLifeMacApp.swift`

- [ ] **Step 1: Implement the environment** (mirrors iOS `CaptureEnvironment`, adds hotkeys + recording-state publishing):

```swift
import Foundation
import SwiftData
import Combine
import PRLifeKit

@MainActor
final class MacCaptureEnvironment: ObservableObject {
    static let shared = MacCaptureEnvironment()

    let container: ModelContainer
    let store: SwiftDataCaptureStore
    let coordinator: CaptureCoordinator
    let api: LifeAPIClient
    private let hotKeys = CarbonHotKeyManager()

    @Published private(set) var isRecording = false
    @Published private(set) var recordingContext: CaptureContext?

    private init() {
        let config = ModelConfiguration(groupContainer: .identifier(AppGroup.id))
        container = try! ModelContainer(for: CaptureEntity.self, configurations: config)
        store = SwiftDataCaptureStore(context: ModelContext(container))

        api = LifeAPIClient(configurationProvider: {
            let trimmed = KeychainConfig.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (URL(string: trimmed), KeychainConfig.token)
        })
        let gate = UploadGate(reachability: PathMonitorReachability(),
                              wifiOnly: UserDefaults.standard.bool(forKey: "wifiOnly"))
        coordinator = CaptureCoordinator(store: store, recorder: MacAudioRecorderService(),
                                         transcriber: SpeechTranscriber(), api: api, gate: gate)

        CaptureActionRouter.start = { [weak self] ctx in
            guard let self else { return }
            CaptureControlChannel.clearStopRequest()
            await self.coordinator.handle(.startCapture(context: ctx))
            self.isRecording = self.coordinator.isRecording
            self.recordingContext = self.coordinator.isRecording ? ctx : nil
        }
        CaptureActionRouter.stop = { [weak self] in
            guard let self else { return }
            await self.coordinator.handle(.stopCapture)
            self.isRecording = false
            self.recordingContext = nil
        }
    }

    func startHotKeys() {
        hotKeys.register(HotKeyBinding.defaults) { context in
            Task { @MainActor in
                if MacCaptureEnvironment.shared.isRecording {
                    await CaptureActionRouter.stop?()
                } else {
                    await CaptureActionRouter.start?(context)
                }
            }
        }
    }

    /// Toggle entry point used by popover buttons / menu items.
    func toggleCapture(_ context: CaptureContext) {
        Task {
            if isRecording { await CaptureActionRouter.stop?() }
            else { await CaptureActionRouter.start?(context) }
        }
    }

    func stopCapture() { Task { await CaptureActionRouter.stop?() } }
}
```

- [ ] **Step 2: Start hotkeys at launch** — update `PRLifeMacApp.swift`:

```swift
import SwiftUI
import PRLifeKit

@main
struct PRLifeMacApp: App {
    @StateObject private var env = MacCaptureEnvironment.shared

    init() { MacCaptureEnvironment.shared.startHotKeys() }

    var body: some Scene {
        MenuBarExtra("PR Life", systemImage: env.isRecording ? "waveform.circle.fill" : "waveform") {
            Text(env.isRecording ? "Recording \(env.recordingContext?.displayName ?? "")…" : "PR Life_")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 3: Build**

Run: `cd ~/Developer/PRLifeMobile && xcodegen generate && xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add MacApp/MacCaptureEnvironment.swift MacApp/PRLifeMacApp.swift
git commit -m "feat(mac): wire capture coordinator, hotkeys, and recording state

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**Manual QA (flag — first end-to-end capture):** With base URL + token set in Keychain (use a temporary `LocalAPIConfig.plist` or wait for Task 17 Settings), press ⌃⌥W → grant mic + speech permission → speak → press ⌃⌥W again → confirm the menu-bar icon toggles, a `CaptureEntity` is written, and (when configured) the entry reaches the backend.

---

## Phase 4 — Sync service + snapshot

### Task 14: `LifeSyncService` — fetch, cache, reload widgets

**Files:**
- Create: `MacApp/Sync/LifeSyncService.swift`

- [ ] **Step 1: Implement the sync service**:

```swift
import Foundation
import WidgetKit
import PRLifeKit

@MainActor
final class LifeSyncService: ObservableObject {
    enum SyncState: Equatable {
        case idle, syncing, synced(Date), failed(String)
    }

    @Published private(set) var state: SyncState = .idle
    @Published private(set) var snapshot: LifeSnapshot?

    private let api: LifeAPIClient
    private let store: LifeSnapshotStoring
    private var timer: Timer?

    init(api: LifeAPIClient,
         store: LifeSnapshotStoring = FileLifeSnapshotStore(directory: AppGroup.containerURL)) {
        self.api = api
        self.store = store
        self.snapshot = store.load()
        if case let .some(snap) = self.snapshot { state = .synced(snap.lastSync) }
    }

    func startPeriodicRefresh(interval: TimeInterval = 900) {
        Task { await self.refresh() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        state = .syncing
        do {
            async let events = api.fetchEvents(date: nil)
            async let tasks = api.fetchTasks()
            let snap = LifeSnapshot(events: try await events, tasks: try await tasks, lastSync: Date())
            try store.save(snap)
            snapshot = snap
            state = .synced(snap.lastSync)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            let message = (error as? LifeAPIError)?.errorDescription ?? "\(error)"
            state = .failed(message)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd ~/Developer/PRLifeMobile && xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add MacApp/Sync/LifeSyncService.swift
git commit -m "feat(mac): add LifeSyncService writing snapshot + reloading widgets

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Phase 5 — UI surfaces

> UI tasks recreate the exact pixel specs in `~/Downloads/design_handoff_companion_apps/CODEX_PROMPT.md`. They are visual/manual-QA gated (no unit tests). Build each, then run and compare against `screenshots/`. Use `Theme`/`PRLifeTokens` for every color/font (no hardcoded hex in views). All corners square (radius 0), 1px borders, no shadows.

### Task 15: Shared view components

**Files:**
- Create: `MacApp/Theme/Components/SectionLabel.swift` (trailing-underscore DM Mono label, e.g. `UPCOMING_`)
- Create: `MacApp/Theme/Components/SyncDot.swift` (green/amber/red dot + status text)
- Create: `MacApp/Theme/Components/SquareCheckbox.swift` (14×14 / 13×13 / 11×11 square, 1px border)
- Create: `MacApp/Theme/Components/PriorityDot.swift` (5pt circle; high `#ff6c61`, medium `#f5a623`, low `#6f6f6f`)
- Create: `MacApp/Theme/Components/EventRow.swift` (accent bar + name + time + optional countdown)
- Create: `MacApp/Theme/Components/TaskRow.swift` (checkbox + name + priority dot + project label)

- [ ] **Step 1:** Implement each component as a small `View` reading tokens from `Theme`/`PRLifeTokens`. Port the iOS `App/Theme/Components/*` where equivalents exist (`SectionLabel`, `SyncDot`, `StatusBadge`, `CaptureRow`) and adapt the new ones (`EventRow`, `TaskRow`, `PriorityDot`, `SquareCheckbox`) per the per-row specs in CODEX_PROMPT Screens 4–5. Map `LifeTaskPriority` → color here, not in the model.
- [ ] **Step 2: Build** — `xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build` → `** BUILD SUCCEEDED **`.
- [ ] **Step 3: Commit** — `feat(mac): add shared SwiftUI row/label components` (+ trailer).

---

### Task 16: MenuBarExtra popover (Screen 4)

**Files:**
- Create: `MacApp/Screens/MenuBarPopover.swift`
- Modify: `MacApp/PRLifeMacApp.swift` (use the popover as `MenuBarExtra` content; inject `MacCaptureEnvironment` + `LifeSyncService`)

- [ ] **Step 1:** Build `MenuBarPopover` at width 340pt per Screen 4: header (`LIFE_` + sync status from `LifeSyncService.state`), Quick Capture 2×2 grid wired to `env.toggleCapture(_:)` with shortcut hints, Upcoming (today's events from `sync.snapshot?.events`, accent bar + countdown on next), Due Today (`sync.snapshot?.tasks` filtered `isDue(on: todayLocalDate)`), footer (Open PR Life → opens web URL; Settings → opens Settings scene). When `env.isRecording`, the Quick Capture grid shows the active context with a Stop affordance.
- [ ] **Step 2:** On popover appear, call `Task { await sync.refresh() }`.
- [ ] **Step 3: Build** → `** BUILD SUCCEEDED **`.
- [ ] **Step 4: Commit** — `feat(mac): build menu-bar popover (Screen 4)` (+ trailer).

**Manual QA (flag):** Open popover; compare to `screenshots/macos-menu-bar.png`; confirm events/tasks populate when configured, Quick Capture toggles recording.

---

### Task 17: Main window — Today + Captures + Devices tabs, Settings (Screens 5–6)

**Files:**
- Create: `MacApp/Screens/MainWindow.swift` (tab container: Today / Captures / Devices)
- Create: `MacApp/Screens/TodayView.swift` (Screen 5)
- Create: `MacApp/Screens/CapturesView.swift` (local capture history from `store.all()`)
- Create: `MacApp/Screens/DevicesView.swift` (Screen 6: live shortcut tiles from `HotKeyBinding.defaults`, "coming soon" hardware rows, architecture note, PR Life API connection + Sync now)
- Create: `MacApp/Screens/SettingsView.swift` (base URL + token → `KeychainConfig.save`; Wi-Fi-only toggle → `UserDefaults "wifiOnly"`)
- Modify: `MacApp/PRLifeMacApp.swift` (add `Window`/`WindowGroup` + `Settings` scenes; "Open PR Life" menu items)

- [ ] **Step 1:** Build the tabbed main window per Screens 5–6 (title bar, nav tabs, 2-col Today, sync footer; Devices tab content). Captures tab reuses the row pattern from iOS `CaptureRow`. Settings writes to `KeychainConfig` and triggers `sync.refresh()` on save.
- [ ] **Step 2:** Wire "Sync now" (Devices + Today footer) → `sync.refresh()`; "Open PR Life" → `NSWorkspace.shared.open(webURL)`.
- [ ] **Step 3: Build** → `** BUILD SUCCEEDED **`.
- [ ] **Step 4: Commit** — `feat(mac): build main window tabs + settings (Screens 5–6)` (+ trailer).

**Manual QA (flag):** Compare Today/Devices to `screenshots/macos-window-today.png` / `macos-window-devices.png`; enter real base URL + token in Settings, confirm sync populates and persists across relaunch.

---

## Phase 6 — Widgets

### Task 18: `PRLifeMacWidgets` extension + small/medium/large widgets

**Files:**
- Modify: `project.yml` (add `PRLifeMacWidgets` app-extension target, macOS, depends on `PRLifeKit`; add to `PRLifeMac` dependencies)
- Create: `MacWidgets/Info.plist`, `MacWidgets/PRLifeMacWidgets.entitlements` (same App Group)
- Create: `MacWidgets/LifeWidgetBundle.swift`
- Create: `MacWidgets/LifeTimelineProvider.swift` (reads `FileLifeSnapshotStore(directory: AppGroup.containerURL)`)
- Create: `MacWidgets/LifeWidgetViews.swift` (small 158², medium 338×158, large 338×354 per the Widget specs)

- [ ] **Step 1: Add the extension target** to `project.yml`:

```yaml
  PRLifeMacWidgets:
    type: app-extension
    platform: macOS
    sources:
      - MacWidgets
      - path: MacApp/AppGroup.swift
    dependencies:
      - package: PRLifeKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.pramitranjan.prlife.mac.widgets
        SWIFT_VERSION: "5.9"
        GENERATE_INFOPLIST_FILE: NO
        INFOPLIST_FILE: MacWidgets/Info.plist
        CODE_SIGN_ENTITLEMENTS: MacWidgets/PRLifeMacWidgets.entitlements
        MACOSX_DEPLOYMENT_TARGET: "14.0"
```
Add `- target: PRLifeMacWidgets` to the `PRLifeMac` target's `dependencies`.

- [ ] **Step 2: TimelineProvider** reads the snapshot (never the network):

```swift
import WidgetKit
import PRLifeKit

struct LifeEntry: TimelineEntry {
    let date: Date
    let snapshot: LifeSnapshot?
}

struct LifeTimelineProvider: TimelineProvider {
    private let store = FileLifeSnapshotStore(directory: AppGroup.containerURL)

    func placeholder(in context: Context) -> LifeEntry { LifeEntry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (LifeEntry) -> Void) {
        completion(LifeEntry(date: Date(), snapshot: store.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LifeEntry>) -> Void) {
        let entry = LifeEntry(date: Date(), snapshot: store.load())
        let next = Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
```

- [ ] **Step 3:** Implement `LifeWidgetBundle` + three `Widget` families (`systemSmall/Medium/Large`) with views per the Widget specs, reading `entry.snapshot?.events` / `.tasks`. Empty-state mirrors the spec's placeholder text.
- [ ] **Step 4: Build** — `cd ~/Developer/PRLifeMobile && xcodegen generate && xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build` → `** BUILD SUCCEEDED **`.
- [ ] **Step 5: Commit** — `feat(mac): add WidgetKit extension with small/medium/large widgets` (+ trailer).

**Manual QA (flag):** Add each widget size to Notification Center / desktop; confirm they show cached events/tasks and refresh after the app syncs (`WidgetCenter.reloadAllTimelines`). Compare to `screenshots/widget-*.png`.

---

## Phase 7 — Final verification

### Task 19: Full-suite + integration QA

- [ ] **Step 1:** `cd ~/Developer/PRLifeMobile && swift test` → all kit tests PASS.
- [ ] **Step 2:** `xcodebuild -scheme PRLifeMac -destination 'platform=macOS' build` → `** BUILD SUCCEEDED **`.
- [ ] **Step 3 (manual QA checklist):**
  - Menu-bar icon present, no Dock icon; popover matches Screen 4.
  - Settings: enter base URL + `LIFE_MOBILE_TOKEN`; sync populates events + tasks; persists across relaunch.
  - Each hotkey (⌃⌥Space/W/J/I) toggles capture; mic + speech permission prompts appear once; capture uploads to backend and appears in Captures tab.
  - `Esc` / Stop button / repeating the same hotkey stops an active capture.
  - Widgets (all three sizes) show cached data and refresh after a sync.
  - Offline / unconfigured shows last snapshot + a disconnected sync indicator (no crash).
- [ ] **Step 4:** Code-quality review (`superpowers:code-reviewer`) over the macOS diff; spec-compliance review against `docs/specs/2026-06-20-...`.

---

## Spec coverage map

- Menu-bar popover (Screen 4) → Task 16
- Main window Today/Captures/Devices (Screens 5–6) → Task 17
- Widgets small/medium/large → Task 18
- Global hotkeys (⌃⌥Space/W/J/I) → Tasks 5, 12, 13
- Desktop-mic capture → Tasks 9, 13
- On-device transcription → Task 10
- Events/tasks reads + models → Tasks 1–3
- Snapshot cache (app-writes/widget-reads) → Tasks 4, 14, 18
- Hardware abstraction seam (`PRLifeAction`/`CaptureActionRouter`) → reused; documented on Devices tab (Task 17)
- Settings/Keychain config → Tasks 8, 17
- Monorepo target + Theme/fonts/AppGroup re-add → Tasks 6, 7
- Toggle capture model → Tasks 13, 16
- Deferred (notifications, multi-day rollup, custom shortcuts, real hardware) → not in plan (per spec §12)
