# PR Life iOS Capture App — V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native iOS app that records audio reliably, transcribes it on-device, and POSTs the text to the existing PR Life `/api/life/entries` endpoint as a `voice` entry — including starting a capture from outside the app.

**Architecture:** A pure-Swift SPM package (`PRLifeKit`) holds all testable logic and protocols (models, capture coordinator, API client, store/recorder/transcriber protocols, design tokens). The app target supplies the SwiftUI UI and the concrete platform implementations (SwiftData, AVFoundation, Speech, Keychain, NWPathMonitor, App Intents). A widget extension hosts the Live Activity. The project file is generated from a checked-in `project.yml` via XcodeGen so it is reproducible from the CLI.

**Tech Stack:** Swift 6.3 / Xcode 26.5, iOS 17.0+, SwiftUI, SwiftData, AVFoundation, Speech, ActivityKit + WidgetKit, App Intents, XcodeGen. Backend: one small change to the Next.js portfolio repo (`lib/life/env.ts`, `lib/life/auth.ts`).

**Spec:** `~/Developer/PRLifeMobile/docs/specs/2026-06-19-pr-life-ios-capture-app-design.md`

**Repos:**
- App: `~/Developer/PRLifeMobile` (this plan's primary repo; `git init` in Task 1)
- Backend: `~/portfolio` (only touched in Phase 6)

---

## Conventions

- **Two test runners.** `PRLifeKit` logic is tested with `swift test` (fast, no simulator). App/widget/system code is verified with `xcodebuild` builds and on-device manual checks (AVFoundation/Speech/ActivityKit cannot be unit-tested meaningfully).
- **Pick a simulator once.** Run `xcrun simctl list devices available | grep iPhone` and use an available name in the `-destination` flags below. The plan writes `name=iPhone 16` — substitute whatever exists.
- **Commit after every task** (each task ends in a commit step).
- **Conventional commit messages** (`feat:`, `test:`, `chore:`, `fix:`).

---

## File Structure

```
~/Developer/PRLifeMobile/
├── project.yml                     # XcodeGen manifest (targets, settings)
├── Package.swift                   # PRLifeKit SPM package
├── Sources/PRLifeKit/
│   ├── Model/
│   │   ├── CaptureStatus.swift     # enum: recording…done/failed
│   │   ├── CaptureContext.swift    # work/ideas/journal/quick → projectSlug
│   │   ├── CaptureRecord.swift     # plain value type (UI/transport DTO)
│   │   └── PRLifeAction.swift      # startCapture(context)/stopCapture
│   ├── API/
│   │   ├── LifeAPIClient.swift     # URLSession POST + queue logic
│   │   ├── EntryPayload.swift      # Codable request body
│   │   └── Reachability.swift      # protocol + types
│   ├── Capture/
│   │   ├── CaptureStoring.swift    # store protocol
│   │   ├── AudioRecording.swift    # recorder protocol + RecordingState
│   │   ├── Transcribing.swift      # transcriber protocol + errors
│   │   └── CaptureCoordinator.swift# the action router
│   └── Theme/
│       └── PRLifeTokens.swift      # hex colors, type sizes, spacing (platform-free)
├── Tests/PRLifeKitTests/
│   ├── LifeAPIClientTests.swift
│   ├── CaptureCoordinatorTests.swift
│   ├── CaptureStoreTests.swift
│   ├── CaptureContextTests.swift
│   └── Support/                    # fakes: FakeStore, FakeRecorder, FakeTranscriber, MockURLProtocol, FakeReachability
├── App/
│   ├── PRLifeMobileApp.swift       # @main, SwiftData container, DI
│   ├── Theme/
│   │   ├── PRLifeTheme.swift       # SwiftUI Color/Font from PRLifeTokens, font registration
│   │   └── Components/             # SectionLabel, StatusBadge, SquareToggle, RecordButton, CaptureRow, SyncDot
│   ├── Capture/
│   │   ├── SwiftDataCaptureStore.swift   # @Model + CaptureStoring impl
│   │   ├── AVAudioRecorderService.swift  # AudioRecording impl
│   │   └── SpeechTranscriber.swift       # Transcribing impl
│   ├── Net/
│   │   ├── KeychainConfig.swift          # base URL + token
│   │   └── PathMonitorReachability.swift # Reachability impl
│   ├── Intents/
│   │   ├── StartCaptureIntent.swift
│   │   ├── StopCaptureIntent.swift
│   │   └── PRLifeShortcuts.swift
│   ├── Activity/
│   │   └── RecordingAttributes.swift     # ActivityKit attributes/state (shared w/ widget)
│   ├── Screens/
│   │   ├── MainView.swift
│   │   └── DevicesView.swift
│   └── Resources/
│       ├── Info.plist
│       └── Fonts/                        # ClashDisplay*.otf, DMMono*.ttf
├── Widgets/
│   ├── PRLifeWidgetsBundle.swift
│   └── RecordingLiveActivity.swift
└── docs/                                 # spec + this plan
```

**Decomposition rationale:** everything that can be tested without a device lives in `PRLifeKit` behind protocols. The app target only wires concrete platform APIs to those protocols. The `RecordingAttributes` type is shared between app and widget (both targets include that one file via `project.yml`).

---

## Phase 0 — Project Scaffold

### Task 1: Initialize repo + SPM package

**Files:**
- Create: `~/Developer/PRLifeMobile/Package.swift`
- Create: `~/Developer/PRLifeMobile/Sources/PRLifeKit/Placeholder.swift`
- Create: `~/Developer/PRLifeMobile/Tests/PRLifeKitTests/SmokeTests.swift`
- Create: `~/Developer/PRLifeMobile/.gitignore`

- [ ] **Step 1: Init git and gitignore**

```bash
cd ~/Developer/PRLifeMobile
git init
cat > .gitignore <<'EOF'
.DS_Store
.build/
DerivedData/
*.xcodeproj
xcuserdata/
*.xcworkspace
!docs/**
EOF
```

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PRLifeKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PRLifeKit", targets: ["PRLifeKit"])
    ],
    targets: [
        .target(name: "PRLifeKit"),
        .testTarget(name: "PRLifeKitTests", dependencies: ["PRLifeKit"])
    ]
)
```

- [ ] **Step 3: Add a placeholder source + smoke test**

`Sources/PRLifeKit/Placeholder.swift`:
```swift
public enum PRLifeKit {
    public static let version = "0.1.0"
}
```

`Tests/PRLifeKitTests/SmokeTests.swift`:
```swift
import XCTest
@testable import PRLifeKit

final class SmokeTests: XCTestCase {
    func test_version_isSet() {
        XCTAssertEqual(PRLifeKit.version, "0.1.0")
    }
}
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `cd ~/Developer/PRLifeMobile && swift test`
Expected: `Test Suite 'All tests' passed` with 1 test.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore: init PRLifeKit swift package"
```

---

### Task 2: XcodeGen manifest, app + widget targets

**Files:**
- Create: `~/Developer/PRLifeMobile/project.yml`
- Create: `App/PRLifeMobileApp.swift`
- Create: `App/Screens/MainView.swift` (temporary stub)
- Create: `App/Resources/Info.plist`
- Create: `Widgets/PRLifeWidgetsBundle.swift` (temporary stub)

- [ ] **Step 1: Ensure XcodeGen is installed**

Run: `which xcodegen || brew install xcodegen`
Expected: a path to `xcodegen`.

- [ ] **Step 2: Write `project.yml`**

```yaml
name: PRLifeMobile
options:
  bundleIdPrefix: com.pramitranjan.prlife
  deploymentTarget:
    iOS: "17.0"
packages:
  PRLifeKit:
    path: .
targets:
  PRLifeMobile:
    type: application
    platform: iOS
    sources:
      - App
    dependencies:
      - package: PRLifeKit
      - target: PRLifeWidgets
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.pramitranjan.prlife
        INFOPLIST_FILE: App/Resources/Info.plist
        SWIFT_VERSION: "5.9"
        GENERATE_INFOPLIST_FILE: NO
        CODE_SIGN_STYLE: Automatic
    info:
      path: App/Resources/Info.plist
  PRLifeWidgets:
    type: app-extension
    platform: iOS
    sources:
      - Widgets
      - path: App/Activity/RecordingAttributes.swift   # shared file
    dependencies:
      - package: PRLifeKit
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.pramitranjan.prlife.widgets
        SWIFT_VERSION: "5.9"
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_NSExtensionPointIdentifier: com.apple.widgetkit-extension
schemes:
  PRLifeMobile:
    build:
      targets:
        PRLifeMobile: all
    run:
      config: Debug
    test:
      targets:
        - PRLifeKitTests
```

> Note: `RecordingAttributes.swift` is referenced before it exists; create the stub in Task 17. Until then, comment out the widget `sources` line for that file OR create an empty `App/Activity/RecordingAttributes.swift` now. Create the empty file now to keep generation working:

- [ ] **Step 3: Create stub files so generation succeeds**

`App/Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>PR Life</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>UILaunchScreen</key><dict/>
  <key>NSMicrophoneUsageDescription</key>
  <string>PR Life records your voice so it can capture and transcribe your thoughts.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>PR Life transcribes your recordings on-device to turn them into text entries.</string>
  <key>UIBackgroundModes</key>
  <array><string>audio</string></array>
</dict>
</plist>
```

`App/PRLifeMobileApp.swift`:
```swift
import SwiftUI

@main
struct PRLifeMobileApp: App {
    var body: some Scene {
        WindowGroup { MainView() }
    }
}
```

`App/Screens/MainView.swift`:
```swift
import SwiftUI

struct MainView: View {
    var body: some View { Text("PR Life").padding() }
}
```

`App/Activity/RecordingAttributes.swift`:
```swift
// Stub — real ActivityKit attributes added in Task 17.
```

`Widgets/PRLifeWidgetsBundle.swift`:
```swift
import WidgetKit
import SwiftUI

@main
struct PRLifeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Live Activity registered in Task 18.
        EmptyWidgetPlaceholder()
    }
}

struct EmptyWidgetPlaceholder: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "placeholder", provider: PlaceholderProvider()) { _ in
            Text("PR Life")
        }
    }
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) { completion(SimpleEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
    }
}
struct SimpleEntry: TimelineEntry { let date: Date }
```

- [ ] **Step 4: Generate and build**

Run:
```bash
cd ~/Developer/PRLifeMobile && xcodegen generate
xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "chore: xcodegen project with app + widget targets"
```

---

## Phase 1 — Core Models (TDD, PRLifeKit)

### Task 3: CaptureStatus + CaptureContext

**Files:**
- Create: `Sources/PRLifeKit/Model/CaptureStatus.swift`
- Create: `Sources/PRLifeKit/Model/CaptureContext.swift`
- Create: `Tests/PRLifeKitTests/CaptureContextTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/PRLifeKitTests/CaptureContextTests.swift`:
```swift
import XCTest
@testable import PRLifeKit

final class CaptureContextTests: XCTestCase {
    func test_projectSlug_mapsKnownContexts() {
        XCTAssertEqual(CaptureContext.work.projectSlug, "work")
        XCTAssertEqual(CaptureContext.journal.projectSlug, "journal")
        XCTAssertEqual(CaptureContext.ideas.projectSlug, "ideas")
    }

    func test_quick_hasNoProjectSlug() {
        XCTAssertNil(CaptureContext.quick.projectSlug)
    }

    func test_status_isTerminal() {
        XCTAssertTrue(CaptureStatus.done.isTerminal)
        XCTAssertTrue(CaptureStatus.failed.isTerminal)
        XCTAssertFalse(CaptureStatus.recording.isTerminal)
        XCTAssertFalse(CaptureStatus.processing.isTerminal)
    }
}
```

- [ ] **Step 2: Run, expect FAIL**

Run: `swift test --filter CaptureContextTests`
Expected: FAIL — `CaptureContext`/`CaptureStatus` undefined.

- [ ] **Step 3: Implement**

`Sources/PRLifeKit/Model/CaptureStatus.swift`:
```swift
import Foundation

public enum CaptureStatus: String, Codable, Sendable, CaseIterable {
    case recording
    case processing   // transcribing
    case uploading
    case done
    case failed

    public var isTerminal: Bool { self == .done || self == .failed }

    /// Display label used in the UI status badge, e.g. "PROCESSING_".
    public var badgeLabel: String {
        switch self {
        case .recording: return "RECORDING_"
        case .processing: return "PROCESSING_"
        case .uploading: return "UPLOADING_"
        case .done: return "DONE_"
        case .failed: return "FAILED_"
        }
    }
}
```

`Sources/PRLifeKit/Model/CaptureContext.swift`:
```swift
import Foundation

public enum CaptureContext: String, Codable, Sendable, CaseIterable {
    case quick
    case work
    case journal
    case ideas

    /// Maps to PR Life `projectSlug`. `quick` carries no project context.
    public var projectSlug: String? {
        self == .quick ? nil : rawValue
    }

    public var displayName: String {
        switch self {
        case .quick: return "Quick Capture"
        case .work: return "Work"
        case .journal: return "Journal"
        case .ideas: return "Ideas"
        }
    }
}
```

- [ ] **Step 4: Run, expect PASS**

Run: `swift test --filter CaptureContextTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: CaptureStatus and CaptureContext models"
```

---

### Task 4: CaptureRecord value type + PRLifeAction

**Files:**
- Create: `Sources/PRLifeKit/Model/CaptureRecord.swift`
- Create: `Sources/PRLifeKit/Model/PRLifeAction.swift`
- Create: `Tests/PRLifeKitTests/CaptureRecordTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PRLifeKit

final class CaptureRecordTests: XCTestCase {
    func test_init_defaults() {
        let r = CaptureRecord(context: .work)
        XCTAssertEqual(r.status, .recording)
        XCTAssertEqual(r.context, .work)
        XCTAssertNil(r.transcript)
        XCTAssertNil(r.serverEntryId)
        XCTAssertEqual(r.retryCount, 0)
    }

    func test_action_equatable() {
        XCTAssertEqual(PRLifeAction.startCapture(context: .ideas),
                       PRLifeAction.startCapture(context: .ideas))
        XCTAssertNotEqual(PRLifeAction.startCapture(context: .ideas),
                          PRLifeAction.stopCapture)
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter CaptureRecordTests`

- [ ] **Step 3: Implement**

`Sources/PRLifeKit/Model/CaptureRecord.swift`:
```swift
import Foundation

public struct CaptureRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var duration: TimeInterval
    public var context: CaptureContext
    public var audioFileName: String?     // relative to the captures directory
    public var transcript: String?
    public var status: CaptureStatus
    public var serverEntryId: String?
    public var lastError: String?
    public var retryCount: Int

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        context: CaptureContext,
        audioFileName: String? = nil,
        transcript: String? = nil,
        status: CaptureStatus = .recording,
        serverEntryId: String? = nil,
        lastError: String? = nil,
        retryCount: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.context = context
        self.audioFileName = audioFileName
        self.transcript = transcript
        self.status = status
        self.serverEntryId = serverEntryId
        self.lastError = lastError
        self.retryCount = retryCount
    }
}
```

`Sources/PRLifeKit/Model/PRLifeAction.swift`:
```swift
import Foundation

/// The single internal action vocabulary every input source maps to.
public enum PRLifeAction: Equatable, Sendable {
    case startCapture(context: CaptureContext)
    case stopCapture
}
```

- [ ] **Step 4: Run, expect PASS** — `swift test --filter CaptureRecordTests`

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: CaptureRecord and PRLifeAction"`

---

## Phase 2 — LifeAPIClient (TDD, PRLifeKit)

### Task 5: EntryPayload + request building

**Files:**
- Create: `Sources/PRLifeKit/API/EntryPayload.swift`
- Create: `Sources/PRLifeKit/API/LifeAPIClient.swift`
- Create: `Tests/PRLifeKitTests/Support/MockURLProtocol.swift`
- Create: `Tests/PRLifeKitTests/LifeAPIClientTests.swift`

- [ ] **Step 1: Write the failing test (request shape + auth header)**

`Tests/PRLifeKitTests/Support/MockURLProtocol.swift`:
```swift
import Foundation

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // URLProtocol strips httpBody for streamed bodies; capture via bodyStream.
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            buffer.deallocate(); stream.close()
            MockURLProtocol.lastRequestBody = data
        } else {
            MockURLProtocol.lastRequestBody = request.httpBody
        }
        do {
            let (response, data) = try MockURLProtocol.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
```

`Tests/PRLifeKitTests/LifeAPIClientTests.swift`:
```swift
import XCTest
@testable import PRLifeKit

final class LifeAPIClientTests: XCTestCase {
    private func makeClient() -> LifeAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        return LifeAPIClient(
            baseURL: URL(string: "https://example.com")!,
            token: "secret-token",
            session: session
        )
    }

    func test_upload_buildsAuthorizedJSONPost() async throws {
        MockURLProtocol.handler = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.absoluteString, "https://example.com/api/life/entries")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let body = #"{"entry":{"id":"abc123"}}"#.data(using: .utf8)!
            return (resp, body)
        }
        let client = makeClient()
        let entryId = try await client.upload(content: "hello world", projectSlug: "work")

        let sent = try XCTUnwrap(MockURLProtocol.lastRequestBody)
        let payload = try JSONDecoder().decode(EntryPayload.self, from: sent)
        XCTAssertEqual(payload.content, "hello world")
        XCTAssertEqual(payload.source, "voice")
        XCTAssertEqual(payload.projectSlug, "work")
        XCTAssertEqual(entryId, "abc123")
    }

    func test_upload_throwsOnServerError() async {
        MockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (resp, Data("{\"error\":\"boom\"}".utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.upload(content: "x", projectSlug: nil)
            XCTFail("expected throw")
        } catch let LifeAPIError.server(status, _) {
            XCTAssertEqual(status, 500)
        } catch { XCTFail("wrong error: \(error)") }
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter LifeAPIClientTests`

- [ ] **Step 3: Implement**

`Sources/PRLifeKit/API/EntryPayload.swift`:
```swift
import Foundation

public struct EntryPayload: Codable, Equatable, Sendable {
    public let content: String
    public let source: String        // always "voice" for V1
    public let projectSlug: String?

    public init(content: String, source: String = "voice", projectSlug: String?) {
        self.content = content
        self.source = source
        self.projectSlug = projectSlug
    }
}

private struct EntryResponse: Decodable {
    struct Entry: Decodable { let id: String }
    let entry: Entry
}
```

`Sources/PRLifeKit/API/LifeAPIClient.swift`:
```swift
import Foundation

public enum LifeAPIError: Error, Equatable {
    case server(status: Int, body: String)
    case decoding
    case notConfigured
}

public final class LifeAPIClient: @unchecked Sendable {
    private let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    /// POSTs a voice entry. Returns the server entry id on success.
    @discardableResult
    public func upload(content: String, projectSlug: String?) async throws -> String? {
        let url = baseURL.appendingPathComponent("api/life/entries")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = EntryPayload(content: content, projectSlug: projectSlug)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LifeAPIError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            throw LifeAPIError.server(status: http.statusCode,
                                      body: String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONDecoder().decode(EntryResponse.self, from: data))?.entry.id
    }
}
```

- [ ] **Step 4: Run, expect PASS** — `swift test --filter LifeAPIClientTests`

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: LifeAPIClient with JSON voice-entry upload"`

---

### Task 6: Reachability protocol + WiFi-only gate

**Files:**
- Create: `Sources/PRLifeKit/API/Reachability.swift`
- Create: `Tests/PRLifeKitTests/Support/FakeReachability.swift`
- Modify: `Tests/PRLifeKitTests/LifeAPIClientTests.swift` (add gate tests in a new file)
- Create: `Tests/PRLifeKitTests/UploadGateTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/PRLifeKitTests/Support/FakeReachability.swift`:
```swift
@testable import PRLifeKit

final class FakeReachability: ReachabilityProviding, @unchecked Sendable {
    var status: ConnectivityStatus
    init(_ status: ConnectivityStatus) { self.status = status }
    func current() -> ConnectivityStatus { status }
}
```

`Tests/PRLifeKitTests/UploadGateTests.swift`:
```swift
import XCTest
@testable import PRLifeKit

final class UploadGateTests: XCTestCase {
    func test_wifiOnly_blocksOnCellular() {
        let gate = UploadGate(reachability: FakeReachability(.cellular), wifiOnly: true)
        XCTAssertFalse(gate.canUploadNow())
    }
    func test_wifiOnly_allowsOnWifi() {
        let gate = UploadGate(reachability: FakeReachability(.wifi), wifiOnly: true)
        XCTAssertTrue(gate.canUploadNow())
    }
    func test_wifiOff_allowsOnCellular() {
        let gate = UploadGate(reachability: FakeReachability(.cellular), wifiOnly: false)
        XCTAssertTrue(gate.canUploadNow())
    }
    func test_offline_blocksAlways() {
        let gate = UploadGate(reachability: FakeReachability(.offline), wifiOnly: false)
        XCTAssertFalse(gate.canUploadNow())
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter UploadGateTests`

- [ ] **Step 3: Implement**

`Sources/PRLifeKit/API/Reachability.swift`:
```swift
import Foundation

public enum ConnectivityStatus: Sendable, Equatable {
    case wifi, cellular, offline
}

public protocol ReachabilityProviding: Sendable {
    func current() -> ConnectivityStatus
}

public struct UploadGate {
    private let reachability: ReachabilityProviding
    private let wifiOnly: Bool

    public init(reachability: ReachabilityProviding, wifiOnly: Bool) {
        self.reachability = reachability
        self.wifiOnly = wifiOnly
    }

    public func canUploadNow() -> Bool {
        switch reachability.current() {
        case .offline: return false
        case .cellular: return !wifiOnly
        case .wifi: return true
        }
    }
}
```

- [ ] **Step 4: Run, expect PASS** — `swift test --filter UploadGateTests`

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: reachability + WiFi-only upload gate"`

---

## Phase 3 — CaptureStore protocol + in-memory fake (TDD)

### Task 7: CaptureStoring protocol + status transitions

**Files:**
- Create: `Sources/PRLifeKit/Capture/CaptureStoring.swift`
- Create: `Tests/PRLifeKitTests/Support/InMemoryCaptureStore.swift`
- Create: `Tests/PRLifeKitTests/CaptureStoreTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/PRLifeKitTests/Support/InMemoryCaptureStore.swift`:
```swift
import Foundation
@testable import PRLifeKit

final class InMemoryCaptureStore: CaptureStoring, @unchecked Sendable {
    private(set) var records: [CaptureRecord] = []

    func insert(_ record: CaptureRecord) { records.insert(record, at: 0) }

    func update(id: UUID, _ mutate: (inout CaptureRecord) -> Void) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        mutate(&records[i])
    }

    func all() -> [CaptureRecord] { records }

    func record(id: UUID) -> CaptureRecord? { records.first { $0.id == id } }
}
```

`Tests/PRLifeKitTests/CaptureStoreTests.swift`:
```swift
import XCTest
@testable import PRLifeKit

final class CaptureStoreTests: XCTestCase {
    func test_insert_thenUpdateStatus() {
        let store = InMemoryCaptureStore()
        let rec = CaptureRecord(context: .quick)
        store.insert(rec)
        store.update(id: rec.id) { $0.status = .processing }
        XCTAssertEqual(store.record(id: rec.id)?.status, .processing)
    }

    func test_all_returnsNewestFirst() {
        let store = InMemoryCaptureStore()
        let a = CaptureRecord(createdAt: Date(timeIntervalSince1970: 1), context: .work)
        let b = CaptureRecord(createdAt: Date(timeIntervalSince1970: 2), context: .ideas)
        store.insert(a); store.insert(b)
        XCTAssertEqual(store.all().first?.id, b.id)
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter CaptureStoreTests`

- [ ] **Step 3: Implement protocol**

`Sources/PRLifeKit/Capture/CaptureStoring.swift`:
```swift
import Foundation

public protocol CaptureStoring: AnyObject, Sendable {
    func insert(_ record: CaptureRecord)
    func update(id: UUID, _ mutate: (inout CaptureRecord) -> Void)
    func all() -> [CaptureRecord]
    func record(id: UUID) -> CaptureRecord?
}
```

- [ ] **Step 4: Run, expect PASS** — `swift test --filter CaptureStoreTests`

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: CaptureStoring protocol + in-memory test store"`

---

## Phase 4 — AudioRecording + Transcribing protocols + CaptureCoordinator (TDD)

### Task 8: AudioRecording + Transcribing protocols and fakes

**Files:**
- Create: `Sources/PRLifeKit/Capture/AudioRecording.swift`
- Create: `Sources/PRLifeKit/Capture/Transcribing.swift`
- Create: `Tests/PRLifeKitTests/Support/FakeRecorder.swift`
- Create: `Tests/PRLifeKitTests/Support/FakeTranscriber.swift`

- [ ] **Step 1: Implement protocols (no test yet; exercised in Task 9)**

`Sources/PRLifeKit/Capture/AudioRecording.swift`:
```swift
import Foundation

public enum RecordingError: Error, Equatable { case permissionDenied, sessionFailed(String) }

public protocol AudioRecording: AnyObject, Sendable {
    /// Starts recording, returns the audio file name (relative to captures dir).
    func start() async throws -> String
    /// Stops recording, returns final duration in seconds.
    func stop() async -> TimeInterval
    var isRecording: Bool { get }
}
```

`Sources/PRLifeKit/Capture/Transcribing.swift`:
```swift
import Foundation

public enum TranscriptionError: Error, Equatable {
    case permissionDenied
    case recognizerUnavailable
    case emptyTranscript
    case systemError(String)
}

public protocol Transcribing: AnyObject, Sendable {
    func transcribe(fileName: String) async throws -> String
}
```

- [ ] **Step 2: Implement the fakes**

`Tests/PRLifeKitTests/Support/FakeRecorder.swift`:
```swift
import Foundation
@testable import PRLifeKit

final class FakeRecorder: AudioRecording, @unchecked Sendable {
    var isRecording = false
    var startError: RecordingError?
    var fileName = "capture-1.m4a"
    var duration: TimeInterval = 12

    func start() async throws -> String {
        if let e = startError { throw e }
        isRecording = true
        return fileName
    }
    func stop() async -> TimeInterval { isRecording = false; return duration }
}
```

`Tests/PRLifeKitTests/Support/FakeTranscriber.swift`:
```swift
import Foundation
@testable import PRLifeKit

final class FakeTranscriber: Transcribing, @unchecked Sendable {
    var result: Result<String, TranscriptionError> = .success("hello")
    func transcribe(fileName: String) async throws -> String {
        switch result { case .success(let s): return s; case .failure(let e): throw e }
    }
}
```

- [ ] **Step 3: Build tests target** — `swift build --build-tests`
Expected: builds clean.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat: AudioRecording + Transcribing protocols and fakes"`

---

### Task 9: CaptureCoordinator — the action router

**Files:**
- Create: `Sources/PRLifeKit/Capture/CaptureCoordinator.swift`
- Create: `Tests/PRLifeKitTests/CaptureCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PRLifeKit

@MainActor
final class CaptureCoordinatorTests: XCTestCase {
    private func makeSUT() -> (CaptureCoordinator, InMemoryCaptureStore, FakeRecorder, FakeTranscriber, LifeAPIClient) {
        let store = InMemoryCaptureStore()
        let recorder = FakeRecorder()
        let transcriber = FakeTranscriber()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = LifeAPIClient(baseURL: URL(string: "https://e.com")!, token: "t",
                                   session: URLSession(configuration: config))
        let sut = CaptureCoordinator(store: store, recorder: recorder,
                                     transcriber: transcriber, api: client,
                                     gate: UploadGate(reachability: FakeReachability(.wifi), wifiOnly: false))
        return (sut, store, recorder, transcriber, client)
    }

    func test_startThenStop_runsFullPipelineToDone() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
             Data(#"{"entry":{"id":"srv1"}}"#.utf8))
        }
        let (sut, store, _, _, _) = makeSUT()
        await sut.handle(.startCapture(context: .work))
        XCTAssertEqual(store.all().first?.status, .recording)

        await sut.handle(.stopCapture)
        let rec = store.all().first
        XCTAssertEqual(rec?.status, .done)
        XCTAssertEqual(rec?.transcript, "hello")
        XCTAssertEqual(rec?.serverEntryId, "srv1")
        XCTAssertEqual(rec?.duration, 12)
    }

    func test_stopWhenNotRecording_isIgnored() async {
        let (sut, store, _, _, _) = makeSUT()
        await sut.handle(.stopCapture)
        XCTAssertTrue(store.all().isEmpty)
    }

    func test_startWhenAlreadyRecording_isIgnored() async {
        let (sut, store, _, _, _) = makeSUT()
        await sut.handle(.startCapture(context: .work))
        await sut.handle(.startCapture(context: .ideas))
        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.context, .work)
    }

    func test_uploadFailure_marksFailedAndKeepsTranscript() async {
        MockURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        let (sut, store, _, _, _) = makeSUT()
        await sut.handle(.startCapture(context: .quick))
        await sut.handle(.stopCapture)
        let rec = store.all().first
        XCTAssertEqual(rec?.status, .failed)
        XCTAssertEqual(rec?.transcript, "hello")     // transcript preserved for retry
        XCTAssertEqual(rec?.retryCount, 1)
    }

    func test_emptyTranscript_marksFailed() async {
        let (sut, store, _, transcriber, _) = makeSUT()
        transcriber.result = .failure(.emptyTranscript)
        await sut.handle(.startCapture(context: .quick))
        await sut.handle(.stopCapture)
        XCTAssertEqual(store.all().first?.status, .failed)
    }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter CaptureCoordinatorTests`

- [ ] **Step 3: Implement**

`Sources/PRLifeKit/Capture/CaptureCoordinator.swift`:
```swift
import Foundation

@MainActor
public final class CaptureCoordinator {
    private let store: CaptureStoring
    private let recorder: AudioRecording
    private let transcriber: Transcribing
    private let api: LifeAPIClient
    private let gate: UploadGate

    private var activeID: UUID?

    public init(store: CaptureStoring, recorder: AudioRecording,
                transcriber: Transcribing, api: LifeAPIClient, gate: UploadGate) {
        self.store = store
        self.recorder = recorder
        self.transcriber = transcriber
        self.api = api
        self.gate = gate
    }

    public var isRecording: Bool { activeID != nil }

    public func handle(_ action: PRLifeAction) async {
        switch action {
        case .startCapture(let context): await start(context)
        case .stopCapture: await stop()
        }
    }

    private func start(_ context: CaptureContext) async {
        guard activeID == nil else { return }              // ignore double-start
        var record = CaptureRecord(context: context, status: .recording)
        do {
            let fileName = try await recorder.start()
            record.audioFileName = fileName
            store.insert(record)
            activeID = record.id
        } catch {
            record.status = .failed
            record.lastError = "\(error)"
            store.insert(record)
        }
    }

    private func stop() async {
        guard let id = activeID else { return }            // ignore stop when idle
        activeID = nil
        let duration = await recorder.stop()
        store.update(id: id) { $0.duration = duration; $0.status = .processing }

        guard let fileName = store.record(id: id)?.audioFileName else {
            store.update(id: id) { $0.status = .failed; $0.lastError = "missing audio" }
            return
        }

        // Transcribe
        let transcript: String
        do {
            transcript = try await transcriber.transcribe(fileName: fileName)
        } catch {
            store.update(id: id) { $0.status = .failed; $0.lastError = "\(error)" }
            return
        }
        store.update(id: id) { $0.transcript = transcript; $0.status = .uploading }

        // Upload
        await upload(id: id, content: transcript,
                     projectSlug: store.record(id: id)?.context.projectSlug)
    }

    /// Uploads a captured transcript; safe to call again for retry.
    public func upload(id: UUID, content: String, projectSlug: String?) async {
        guard gate.canUploadNow() else {
            store.update(id: id) { $0.status = .failed; $0.lastError = "offline/wifi-gated" }
            return
        }
        do {
            let serverId = try await api.upload(content: content, projectSlug: projectSlug)
            store.update(id: id) { $0.serverEntryId = serverId; $0.status = .done; $0.lastError = nil }
        } catch {
            store.update(id: id) { $0.status = .failed; $0.lastError = "\(error)"; $0.retryCount += 1 }
        }
    }
}
```

- [ ] **Step 4: Run, expect PASS** — `swift test --filter CaptureCoordinatorTests`

- [ ] **Step 5: Run the full kit suite** — `swift test`
Expected: all tests pass.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: CaptureCoordinator action router with full pipeline"`

---

## Phase 5 — Design System (PRLifeKit tokens + App theme)

### Task 10: PRLifeTokens (platform-free) + test

**Files:**
- Create: `Sources/PRLifeKit/Theme/PRLifeTokens.swift`
- Create: `Tests/PRLifeKitTests/PRLifeTokensTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PRLifeKit

final class PRLifeTokensTests: XCTestCase {
    func test_accentHex() { XCTAssertEqual(PRLifeTokens.Color.accent, "FF3120") }
    func test_backgroundHex() { XCTAssertEqual(PRLifeTokens.Color.background, "0A0A0A") }
}
```

- [ ] **Step 2: Run, expect FAIL** — `swift test --filter PRLifeTokensTests`

- [ ] **Step 3: Implement**

`Sources/PRLifeKit/Theme/PRLifeTokens.swift`:
```swift
import Foundation

public enum PRLifeTokens {
    public enum Color {
        public static let background = "0A0A0A"
        public static let panel      = "111111"
        public static let panel2     = "141414"
        public static let mutedBG    = "0D0D0D"
        public static let border     = "232323"
        public static let hairline   = "1C1C1C"
        public static let text       = "F5F2ED"
        public static let muted      = "A4A4A4"
        public static let label      = "6F6F6F"
        public static let accent     = "FF3120"
        public static let green      = "5BD07A"
        public static let amber      = "F5A623"
        public static let danger     = "FF6C61"
    }
    public enum Spacing {
        public static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12
        public static let l: CGFloat = 16, xl: CGFloat = 20, xxl: CGFloat = 24
    }
}
```

- [ ] **Step 4: Run, expect PASS** — `swift test --filter PRLifeTokensTests`

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: platform-free PRLife design tokens"`

---

### Task 11: App theme (Color/Font), font bundling, registration

**Files:**
- Create: `App/Theme/PRLifeTheme.swift`
- Add fonts: `App/Resources/Fonts/ClashDisplay-{Regular,Medium,Semibold,Bold}.otf`, `App/Resources/Fonts/DMMono-{Light,Regular,Medium}.ttf`
- Modify: `App/Resources/Info.plist` (add `UIAppFonts`)
- Modify: `project.yml` (ensure `App/Resources/Fonts` are bundled — they are, since `App` is a source dir; confirm resources include)

- [ ] **Step 1: Download fonts**

```bash
cd ~/Developer/PRLifeMobile/App/Resources/Fonts
# Clash Display (Fontshare) and DM Mono (Google Fonts). Download the static files
# from the URLs in the spec's Assets section and place them here with the names above.
```
(If the portfolio already vendors these under `~/portfolio/app/fonts/clash-display`, copy from there.)

- [ ] **Step 2: Register fonts in Info.plist**

Add to `App/Resources/Info.plist` `<dict>`:
```xml
<key>UIAppFonts</key>
<array>
  <string>Fonts/ClashDisplay-Regular.otf</string>
  <string>Fonts/ClashDisplay-Medium.otf</string>
  <string>Fonts/ClashDisplay-Semibold.otf</string>
  <string>Fonts/ClashDisplay-Bold.otf</string>
  <string>Fonts/DMMono-Light.ttf</string>
  <string>Fonts/DMMono-Regular.ttf</string>
  <string>Fonts/DMMono-Medium.ttf</string>
</array>
```

- [ ] **Step 3: Implement the SwiftUI theme bridge**

`App/Theme/PRLifeTheme.swift`:
```swift
import SwiftUI
import PRLifeKit

extension Color {
    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255, opacity: 1)
    }
}

enum Theme {
    static let bg       = Color(hex: PRLifeTokens.Color.background)
    static let panel    = Color(hex: PRLifeTokens.Color.panel)
    static let mutedBG  = Color(hex: PRLifeTokens.Color.mutedBG)
    static let border   = Color(hex: PRLifeTokens.Color.border)
    static let hairline = Color(hex: PRLifeTokens.Color.hairline)
    static let text     = Color(hex: PRLifeTokens.Color.text)
    static let muted    = Color(hex: PRLifeTokens.Color.muted)
    static let label    = Color(hex: PRLifeTokens.Color.label)
    static let accent   = Color(hex: PRLifeTokens.Color.accent)
    static let green    = Color(hex: PRLifeTokens.Color.green)
    static let amber    = Color(hex: PRLifeTokens.Color.amber)
    static let danger   = Color(hex: PRLifeTokens.Color.danger)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = weight == .medium ? "DMMono-Medium" : (weight == .light ? "DMMono-Light" : "DMMono-Regular")
        return .custom(name, size: size)
    }
    static func display(_ size: CGFloat) -> Font { .custom("ClashDisplay-Medium", size: size) }
    static func body(_ size: CGFloat) -> Font { .system(size: size) }
}
```

- [ ] **Step 4: Build, expect success** — `xcodegen generate && xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -3`

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: app theme + font registration"`

---

### Task 12: Theme components

**Files:**
- Create: `App/Theme/Components/SectionLabel.swift`
- Create: `App/Theme/Components/StatusBadge.swift`
- Create: `App/Theme/Components/SquareToggle.swift`
- Create: `App/Theme/Components/SyncDot.swift`
- Create: `App/Theme/Components/RecordButton.swift`
- Create: `App/Theme/Components/CaptureRow.swift`

- [ ] **Step 1: Implement components**

`SectionLabel.swift`:
```swift
import SwiftUI

struct SectionLabel: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text).font(Theme.mono(10)).tracking(2).foregroundStyle(Theme.label)
            Spacer()
            if let trailing { Text(trailing).font(Theme.mono(10)).foregroundStyle(Theme.label.opacity(0.6)) }
        }
    }
}
```

`StatusBadge.swift`:
```swift
import SwiftUI
import PRLifeKit

struct StatusBadge: View {
    let status: CaptureStatus
    private var color: Color {
        switch status {
        case .done: return Theme.green
        case .failed: return Theme.danger
        case .recording, .processing, .uploading: return Theme.accent
        }
    }
    var body: some View {
        Text(status.badgeLabel).font(Theme.mono(10, .medium)).foregroundStyle(color)
    }
}
```

`SquareToggle.swift`:
```swift
import SwiftUI

struct SquareToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Rectangle().fill(Theme.panel)
                    .overlay(Rectangle().stroke(isOn ? Theme.accent.opacity(0.4) : Color(hex: "2E2E2E"), lineWidth: 1))
                    .frame(width: 44, height: 24)
                Rectangle().fill(isOn ? Theme.accent : Color(hex: "3A3A3A"))
                    .frame(width: 16, height: 16).padding(3)
            }
        }.buttonStyle(.plain)
    }
}
```

`SyncDot.swift`:
```swift
import SwiftUI

struct SyncDot: View {
    var connected: Bool = true
    var body: some View {
        Circle().fill(connected ? Theme.green : Theme.label).frame(width: 6, height: 6)
    }
}
```

`RecordButton.swift`:
```swift
import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    var onPress: () -> Void
    var onRelease: () -> Void
    var body: some View {
        HStack {
            Circle().fill(Theme.accent).frame(width: 7, height: 7)
            Text(isRecording ? "RECORDING" : "RECORD").font(Theme.mono(11, .medium)).tracking(2).foregroundStyle(Theme.accent)
            Spacer()
            Text("HOLD TO CAPTURE").font(Theme.mono(10)).foregroundStyle(Color(hex: "3A3A3A"))
        }
        .padding(.horizontal, 20).frame(height: 44)
        .background(Theme.accent.opacity(0.07))
        .overlay(Rectangle().stroke(Theme.accent.opacity(0.35), lineWidth: 1))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !isRecording { onPress() } }
            .onEnded { _ in onRelease() })
    }
}
```

`CaptureRow.swift`:
```swift
import SwiftUI
import PRLifeKit

struct CaptureRow: View {
    let record: CaptureRecord
    private var timeText: String {
        let f = DateFormatter(); f.dateFormat = "EEE, HH:mm"; return f.string(from: record.createdAt)
    }
    private var durationText: String {
        String(format: "%d:%02d", Int(record.duration) / 60, Int(record.duration) % 60)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(timeText).font(Theme.body(14)).foregroundStyle(Theme.text)
                Spacer()
                StatusBadge(status: record.status)
            }
            HStack(spacing: 6) {
                Text(durationText).font(Theme.mono(11)).foregroundStyle(Theme.label)
                Text("·").foregroundStyle(Theme.label)
                Text(record.context.displayName.uppercased()).font(Theme.mono(11)).foregroundStyle(Theme.label)
            }
            if let t = record.transcript, !t.isEmpty {
                Text(t).font(Theme.body(12)).foregroundStyle(Color(hex: "555555")).lineLimit(1)
            }
            if record.status == .processing || record.status == .uploading {
                Rectangle().fill(Theme.accent).frame(height: 2)
            }
        }
        .padding(.vertical, 15).padding(.horizontal, 20)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.hairline), alignment: .top)
    }
}
```

- [ ] **Step 2: Build, expect success** — `xcodegen generate && xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -3`

- [ ] **Step 3: Commit** — `git add -A && git commit -m "feat: PRLife theme components"`

---

## Phase 6 — Backend mobile token (portfolio repo)

### Task 13: Add `LIFE_MOBILE_TOKEN` to the backend

**Repo:** `~/portfolio` (separate from the app repo). Branch off `main`.

**Files:**
- Modify: `lib/life/env.ts`
- Modify: `lib/life/auth.ts`

- [ ] **Step 1: Branch**

```bash
cd ~/portfolio && git checkout -b life-mobile-token
```

- [ ] **Step 2: Expose the optional token in `env.ts`**

In `getLifeServerEnv()`'s returned object, add after the `cronSecret` getter (around line 25):
```ts
    // Optional: dedicated bearer token for native companion apps.
    // Returns null when unset so auth simply skips it.
    get mobileToken(): string | null {
      return process.env.LIFE_MOBILE_TOKEN ?? null
    },
```

- [ ] **Step 3: Accept the mobile token in `auth.ts`**

Replace the bearer-check block in `isAuthenticatedLifeRequest` (lines 14–21) with:
```ts
  const authHeader = request.headers.get('authorization')
  if (!authHeader?.startsWith('Bearer ')) {
    return false
  }

  const presented = authHeader.slice('Bearer '.length)
  const env = getLifeServerEnv()
  if (constantTimeEqual(presented, env.cronSecret)) {
    return true
  }
  if (env.mobileToken && constantTimeEqual(presented, env.mobileToken)) {
    return true
  }
  return false
```

- [ ] **Step 4: Type-check the backend**

Run: `cd ~/portfolio && npx tsc --noEmit`
Expected: no errors (or no NEW errors versus a clean `main`).

- [ ] **Step 5: Commit (do NOT push — user pushes)**

```bash
git add lib/life/env.ts lib/life/auth.ts
git commit -m "feat(life): accept dedicated mobile bearer token"
```

> After merging/deploying, set `LIFE_MOBILE_TOKEN` in the Vercel env and use the same value in the app's Keychain config (Task 15). Locally, add it to `.env.local`.

---

## Phase 7 — Concrete platform implementations (app target)

### Task 14: SwiftData store, AVAudioRecorder, SpeechTranscriber

**Files:**
- Create: `App/Capture/SwiftDataCaptureStore.swift`
- Create: `App/Capture/AVAudioRecorderService.swift`
- Create: `App/Capture/SpeechTranscriber.swift`
- Modify: `App/PRLifeMobileApp.swift` (build SwiftData container + DI)

- [ ] **Step 1: SwiftData-backed store conforming to `CaptureStoring`**

`App/Capture/SwiftDataCaptureStore.swift`:
```swift
import Foundation
import SwiftData
import PRLifeKit

@Model
final class CaptureEntity {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var contextRaw: String
    var audioFileName: String?
    var transcript: String?
    var statusRaw: String
    var serverEntryId: String?
    var lastError: String?
    var retryCount: Int

    init(_ r: CaptureRecord) {
        id = r.id; createdAt = r.createdAt; duration = r.duration
        contextRaw = r.context.rawValue; audioFileName = r.audioFileName
        transcript = r.transcript; statusRaw = r.status.rawValue
        serverEntryId = r.serverEntryId; lastError = r.lastError; retryCount = r.retryCount
    }
    var record: CaptureRecord {
        CaptureRecord(id: id, createdAt: createdAt, duration: duration,
                      context: CaptureContext(rawValue: contextRaw) ?? .quick,
                      audioFileName: audioFileName, transcript: transcript,
                      status: CaptureStatus(rawValue: statusRaw) ?? .failed,
                      serverEntryId: serverEntryId, lastError: lastError, retryCount: retryCount)
    }
    func apply(_ r: CaptureRecord) {
        duration = r.duration; audioFileName = r.audioFileName; transcript = r.transcript
        statusRaw = r.status.rawValue; serverEntryId = r.serverEntryId
        lastError = r.lastError; retryCount = r.retryCount
    }
}

@MainActor
final class SwiftDataCaptureStore: CaptureStoring {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func insert(_ record: CaptureRecord) {
        context.insert(CaptureEntity(record)); try? context.save()
    }
    func update(id: UUID, _ mutate: (inout CaptureRecord) -> Void) {
        guard let e = fetch(id) else { return }
        var r = e.record; mutate(&r); e.apply(r); try? context.save()
    }
    func all() -> [CaptureRecord] {
        let d = FetchDescriptor<CaptureEntity>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? context.fetch(d)) ?? []).map(\.record)
    }
    func record(id: UUID) -> CaptureRecord? { fetch(id)?.record }
    private func fetch(_ id: UUID) -> CaptureEntity? {
        let d = FetchDescriptor<CaptureEntity>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(d).first
    }
}
```

> Note: `CaptureStoring` is declared `Sendable`; this impl is `@MainActor`. Mark the protocol conformance acceptable by keeping all coordinator/store access on the main actor (the coordinator is already `@MainActor`). If the compiler complains about `Sendable`, drop `Sendable` from `CaptureStoring` and keep the protocol `AnyObject` only.

- [ ] **Step 2: AVFoundation recorder**

`App/Capture/AVAudioRecorderService.swift`:
```swift
import Foundation
import AVFoundation
import PRLifeKit

final class AVAudioRecorderService: NSObject, AudioRecording, @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private(set) var isRecording = false

    static var capturesDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start() async throws -> String {
        let granted = await withCheckedContinuation { c in
            AVAudioApplication.requestRecordPermission { c.resume(returning: $0) }
        }
        guard granted else { throw RecordingError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch { throw RecordingError.sessionFailed("\(error)") }

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
            rec.record()
            recorder = rec; isRecording = true
            return name
        } catch { throw RecordingError.sessionFailed("\(error)") }
    }

    func stop() async -> TimeInterval {
        let d = recorder?.currentTime ?? 0
        recorder?.stop(); recorder = nil; isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return d
    }
}
```

- [ ] **Step 3: Speech transcriber (on-device required)**

`App/Capture/SpeechTranscriber.swift`:
```swift
import Foundation
import Speech
import PRLifeKit

final class SpeechTranscriber: Transcribing, @unchecked Sendable {
    func transcribe(fileName: String) async throws -> String {
        let authorized = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard authorized else { throw TranscriptionError.permissionDenied }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let url = AVAudioRecorderService.capturesDir.appendingPathComponent(fileName)
        let request = SFSpeechURLRecognitionRequest(url: url)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            // Spec: do not silently fall back to cloud. Keep audio, surface failure.
            throw TranscriptionError.recognizerUnavailable
        }

        return try await withCheckedThrowingContinuation { cont in
            recognizer.recognitionTask(with: request) { result, error in
                if let error { cont.resume(throwing: TranscriptionError.systemError("\(error)")); return }
                guard let result, result.isFinal else { return }
                let text = result.bestTranscription.formattedString
                if text.isEmpty { cont.resume(throwing: TranscriptionError.emptyTranscript) }
                else { cont.resume(returning: text) }
            }
        }
    }
}
```

- [ ] **Step 4: Build, expect success** — `xcodegen generate && xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -3`

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: SwiftData store + AVFoundation recorder + Speech transcriber"`

---

### Task 15: Keychain config + PathMonitor reachability + app wiring

**Files:**
- Create: `App/Net/KeychainConfig.swift`
- Create: `App/Net/PathMonitorReachability.swift`
- Modify: `App/PRLifeMobileApp.swift`

- [ ] **Step 1: Keychain config (base URL + token)**

`App/Net/KeychainConfig.swift`:
```swift
import Foundation
import Security

enum KeychainConfig {
    private static func set(_ value: String, _ key: String) {
        let data = Data(value.utf8)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
    private static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let d = item as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static var baseURL: String? { get { get("baseURL") } set { set(newValue ?? "", "baseURL") } }
    static var token: String? { get { get("token") } set { set(newValue ?? "", "token") } }
}
```

- [ ] **Step 2: NWPathMonitor reachability**

`App/Net/PathMonitorReachability.swift`:
```swift
import Foundation
import Network
import PRLifeKit

final class PathMonitorReachability: ReachabilityProviding, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var status: ConnectivityStatus = .offline

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let s: ConnectivityStatus
            if path.status != .satisfied { s = .offline }
            else if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) { s = .wifi }
            else { s = .cellular }
            self?.lock.lock(); self?.status = s; self?.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "reachability"))
    }
    func current() -> ConnectivityStatus { lock.lock(); defer { lock.unlock() }; return status }
}
```

- [ ] **Step 3: Wire DI in the app entry point**

`App/PRLifeMobileApp.swift`:
```swift
import SwiftUI
import SwiftData
import PRLifeKit

@main
struct PRLifeMobileApp: App {
    let container: ModelContainer
    @State private var coordinator: CaptureCoordinator
    private let store: SwiftDataCaptureStore

    init() {
        let container = try! ModelContainer(for: CaptureEntity.self)
        self.container = container
        let store = SwiftDataCaptureStore(context: ModelContext(container))
        self.store = store

        let base = URL(string: KeychainConfig.baseURL ?? "http://localhost:3000")!
        let api = LifeAPIClient(baseURL: base, token: KeychainConfig.token ?? "")
        let gate = UploadGate(reachability: PathMonitorReachability(),
                              wifiOnly: UserDefaults.standard.bool(forKey: "wifiOnly"))
        _coordinator = State(initialValue: CaptureCoordinator(
            store: store, recorder: AVAudioRecorderService(),
            transcriber: SpeechTranscriber(), api: api, gate: gate))
    }

    var body: some Scene {
        WindowGroup {
            MainView(coordinator: coordinator, store: store)
        }
        .modelContainer(container)
    }
}
```

- [ ] **Step 4: Build, expect success** (MainView signature updated in Task 16; if building now fails on MainView args, do Task 16 before building).

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: keychain config, reachability, app DI wiring"`

---

## Phase 8 — Screens

### Task 16: MainView (capture + history)

**Files:**
- Modify: `App/Screens/MainView.swift`

- [ ] **Step 1: Implement MainView**

`App/Screens/MainView.swift`:
```swift
import SwiftUI
import PRLifeKit

struct MainView: View {
    let coordinator: CaptureCoordinator
    let store: SwiftDataCaptureStore
    @State private var records: [CaptureRecord] = []
    @State private var isRecording = false
    @State private var context: CaptureContext = .quick

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LIFE_").font(Theme.mono(13, .medium)).tracking(1.3).foregroundStyle(Theme.text)
                Spacer()
                SyncDot()
                Text("SYNCED").font(Theme.mono(10)).foregroundStyle(Theme.label)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.hairline), alignment: .bottom)

            RecordButton(isRecording: isRecording,
                         onPress: { Task { await start() } },
                         onRelease: { Task { await stop() } })
                .padding(14)

            SectionLabel(text: "CAPTURES_", trailing: "\(records.count) total")
                .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(records) { CaptureRow(record: $0) }
                }
            }
            Spacer(minLength: 0)
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { refresh() }
    }

    private func start() async { await coordinator.handle(.startCapture(context: context)); isRecording = true; refresh() }
    private func stop() async { isRecording = false; await coordinator.handle(.stopCapture); refresh() }
    private func refresh() { records = store.all() }
}
```

- [ ] **Step 2: Build + launch in simulator**

```bash
xcodegen generate
xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -3
```
Expected: BUILD SUCCEEDED. Manually run in the simulator: header, record button, empty capture list render with correct dark theme and fonts.

- [ ] **Step 3: Commit** — `git add -A && git commit -m "feat: MainView capture + history screen"`

---

### Task 17: DevicesView (settings) + config editing

**Files:**
- Create: `App/Screens/DevicesView.swift`
- Modify: `App/Screens/MainView.swift` (add nav to Devices)

- [ ] **Step 1: Implement DevicesView**

`App/Screens/DevicesView.swift`:
```swift
import SwiftUI

struct DevicesView: View {
    @State private var baseURL = KeychainConfig.baseURL ?? ""
    @State private var token = KeychainConfig.token ?? ""
    @AppStorage("wifiOnly") private var wifiOnly = false
    @AppStorage("backgroundRecording") private var backgroundRecording = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("PR LIFE API_") {
                    field("Base URL", text: $baseURL)
                    field("Token", text: $token, secure: true)
                    Button("Save") { KeychainConfig.baseURL = baseURL; KeychainConfig.token = token }
                        .font(Theme.mono(11, .medium)).foregroundStyle(Theme.accent)
                }
                section("RECORDING_") {
                    toggleRow("Background recording", "Screen off, app in background", $backgroundRecording)
                    toggleRow("Upload on WiFi only", "Save mobile data", $wifiOnly)
                }
                section("DEVICES_") {
                    mutedRow("PR Life Pebble", "Not paired")
                    mutedRow("Apple Watch", "Coming soon")
                }
            }
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func section(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) { SectionLabel(text: label); content() }
    }
    private func field(_ title: String, text: Binding<String>, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.mono(10)).foregroundStyle(Theme.label)
            Group { if secure { SecureField("", text: text) } else { TextField("", text: text) } }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(Theme.body(13)).foregroundStyle(Theme.text)
                .padding(10).background(Theme.mutedBG)
                .overlay(Rectangle().stroke(Theme.border, lineWidth: 1))
        }
    }
    private func toggleRow(_ title: String, _ subtitle: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.body(13)).foregroundStyle(Theme.text)
                Text(subtitle).font(Theme.mono(10)).foregroundStyle(Theme.label)
            }
            Spacer(); SquareToggle(isOn: isOn)
        }
        .padding(13).background(Theme.panel).overlay(Rectangle().stroke(Color(hex: "1E1E1E"), lineWidth: 1))
    }
    private func mutedRow(_ title: String, _ badge: String) -> some View {
        HStack {
            Text(title).font(Theme.body(13, )).foregroundStyle(Color(hex: "3A3A3A"))
            Spacer()
            Text(badge).font(Theme.mono(9)).foregroundStyle(Color(hex: "2A2A2A"))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 1))
        }
        .padding(14).background(Theme.mutedBG).overlay(Rectangle().stroke(Color(hex: "1A1A1A"), lineWidth: 1))
    }
}
```

> If `Theme.body(13, )` triggers a syntax error, change to `Theme.body(13)`.

- [ ] **Step 2: Add navigation from MainView**

Wrap MainView's content in a `NavigationStack` and add a toolbar link to `DevicesView()`. Minimal change: in `MainView.body`, wrap the outer `VStack` with `NavigationStack { ... .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink("Devices_") { DevicesView() } } } }`.

- [ ] **Step 3: Build, expect success** — `xcodegen generate && xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -3`

- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat: DevicesView settings + config editing"`

---

## Phase 9 — System surfaces (App Intents + Live Activity)

> These cannot be unit-tested; each task ends in a build + an explicit on-device check.

### Task 18: ActivityKit attributes + Live Activity UI

**Files:**
- Modify: `App/Activity/RecordingAttributes.swift` (replace stub)
- Create: `Widgets/RecordingLiveActivity.swift`
- Modify: `Widgets/PRLifeWidgetsBundle.swift`
- Modify: `App/Resources/Info.plist` (add `NSSupportsLiveActivities`)

- [ ] **Step 1: Define shared attributes**

`App/Activity/RecordingAttributes.swift`:
```swift
import ActivityKit
import Foundation

struct RecordingAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var startedAt: Date
        var statusLabel: String   // "Recording", "Processing", "Uploading", "Done"
        var contextName: String
    }
    var captureID: String
}
```

- [ ] **Step 2: Live Activity views**

`Widgets/RecordingLiveActivity.swift`:
```swift
import ActivityKit
import WidgetKit
import SwiftUI

struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { ctx in
            HStack {
                Circle().fill(Color(red: 1, green: 0.19, blue: 0.13)).frame(width: 8, height: 8)
                Text(ctx.state.statusLabel).font(.system(size: 13))
                Spacer()
                Text(ctx.state.startedAt, style: .timer).monospacedDigit().font(.system(size: 15, weight: .medium))
            }
            .padding(14).activityBackgroundTint(Color.black).activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(ctx.state.statusLabel) }
                DynamicIslandExpandedRegion(.trailing) { Text(ctx.state.startedAt, style: .timer).monospacedDigit() }
            } compactLeading: {
                Circle().fill(Color(red: 1, green: 0.19, blue: 0.13)).frame(width: 8, height: 8)
            } compactTrailing: {
                Text(ctx.state.startedAt, style: .timer).monospacedDigit()
            } minimal: {
                Circle().fill(Color(red: 1, green: 0.19, blue: 0.13)).frame(width: 8, height: 8)
            }
        }
    }
}
```

- [ ] **Step 3: Register in bundle + plist**

`Widgets/PRLifeWidgetsBundle.swift` body → `RecordingLiveActivity()` (remove the placeholder widget).
Add to `App/Resources/Info.plist`: `<key>NSSupportsLiveActivities</key><true/>`.

- [ ] **Step 4: Build, expect success** — `xcodegen generate && xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -3`

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: recording Live Activity + Dynamic Island"`

---

### Task 19: Start/stop the Live Activity from the coordinator

**Files:**
- Create: `App/Activity/LiveActivityController.swift`
- Modify: `App/Screens/MainView.swift` (start/stop activity alongside coordinator calls)

- [ ] **Step 1: Implement controller**

`App/Activity/LiveActivityController.swift`:
```swift
import ActivityKit
import Foundation
import PRLifeKit

@MainActor
final class LiveActivityController {
    private var activity: Activity<RecordingAttributes>?

    func start(context: CaptureContext) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = RecordingAttributes(captureID: UUID().uuidString)
        let state = RecordingAttributes.ContentState(startedAt: .now, statusLabel: "Recording",
                                                     contextName: context.displayName)
        activity = try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: nil))
    }
    func update(_ label: String) async {
        guard let activity else { return }
        var s = activity.content.state; s.statusLabel = label
        await activity.update(.init(state: s, staleDate: nil))
    }
    func end() async {
        await activity?.end(nil, dismissalPolicy: .after(.now + 2)); activity = nil
    }
}
```

- [ ] **Step 2: Drive it from MainView**

In `MainView`, add `private let activity = LiveActivityController()`. In `start()` call `activity.start(context: context)` before the coordinator call; in `stop()` call `await activity.update("Processing")`, then after the coordinator returns `await activity.end()`.

- [ ] **Step 3: Build, expect success** — `xcodegen generate && xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -3`

- [ ] **Step 4: On-device check** — run on a physical iPhone: start a capture, lock the phone, confirm the Live Activity + Dynamic Island show the running timer and update to "Processing" on stop.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: drive Live Activity lifecycle from capture flow"`

---

### Task 20: App Intents + Shortcuts (lock-screen / Action Button start)

**Files:**
- Create: `App/Intents/StartCaptureIntent.swift`
- Create: `App/Intents/StopCaptureIntent.swift`
- Create: `App/Intents/PRLifeShortcuts.swift`
- Create: `App/Intents/IntentBridge.swift` (shared access to the coordinator)

- [ ] **Step 1: Bridge so intents reach the live coordinator**

`App/Intents/IntentBridge.swift`:
```swift
import Foundation
import PRLifeKit

/// Set once at app launch so App Intents can route to the running coordinator.
@MainActor
enum IntentBridge {
    static var coordinator: CaptureCoordinator?
    static var activity: LiveActivityController?
}
```
In `PRLifeMobileApp.init`, after building `coordinator`, set `IntentBridge.coordinator = coordinator` (do this in `.task`/`onAppear` on MainView to ensure main-actor timing).

- [ ] **Step 2: Intents (open app so the audio session is reliable)**

`App/Intents/StartCaptureIntent.swift`:
```swift
import AppIntents
import PRLifeKit

struct StartCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Start PR Life Capture"
    static var openAppWhenRun = true     // launching gives us a reliable audio session

    @Parameter(title: "Context") var context: CaptureContextAppEnum?

    @MainActor func perform() async throws -> some IntentResult {
        let ctx = (context ?? .quick).kit
        IntentBridge.activity?.start(context: ctx)
        await IntentBridge.coordinator?.handle(.startCapture(context: ctx))
        return .result()
    }
}

enum CaptureContextAppEnum: String, AppEnum {
    case quick, work, journal, ideas
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Capture Context"
    static var caseDisplayRepresentations: [CaptureContextAppEnum: DisplayRepresentation] = [
        .quick: "Quick", .work: "Work", .journal: "Journal", .ideas: "Ideas"
    ]
    var kit: CaptureContext { CaptureContext(rawValue: rawValue) ?? .quick }
}
```

`App/Intents/StopCaptureIntent.swift`:
```swift
import AppIntents

struct StopCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop PR Life Capture"
    static var openAppWhenRun = false

    @MainActor func perform() async throws -> some IntentResult {
        await IntentBridge.coordinator?.handle(.stopCapture)
        await IntentBridge.activity?.update("Processing")
        await IntentBridge.activity?.end()
        return .result()
    }
}
```

`App/Intents/PRLifeShortcuts.swift`:
```swift
import AppIntents

struct PRLifeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartCaptureIntent(), phrases: ["Start \(.applicationName) capture"],
                    shortTitle: "Start Capture", systemImageName: "mic.fill")
        AppShortcut(intent: StopCaptureIntent(), phrases: ["Stop \(.applicationName) capture"],
                    shortTitle: "Stop Capture", systemImageName: "stop.fill")
    }
}
```

- [ ] **Step 3: Build, expect success** — `xcodegen generate && xcodebuild -scheme PRLifeMobile -destination 'platform=iOS Simulator,name=iPhone 16' build | tail -3`

- [ ] **Step 4: On-device check** — assign `StartCaptureIntent` to the Action Button (or run from Shortcuts) with the phone locked; confirm it launches, records, and the Live Activity appears. Stop via Shortcut; confirm upload.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: App Intents + Shortcuts for external capture triggers"`

---

## Phase 10 — Retry, retention, polish

### Task 21: Retry queue on reconnect

**Files:**
- Create: `App/Capture/RetryService.swift`
- Modify: `App/PRLifeMobileApp.swift` / `MainView` (kick retry on appear + connectivity)

- [ ] **Step 1: Implement retry sweep**

`App/Capture/RetryService.swift`:
```swift
import Foundation
import PRLifeKit

@MainActor
struct RetryService {
    let store: SwiftDataCaptureStore
    let coordinator: CaptureCoordinator

    /// Re-attempts uploads for captures that have a transcript but never reached `.done`.
    func sweep() async {
        for rec in store.all() where rec.status == .failed && rec.transcript != nil && rec.serverEntryId == nil {
            await coordinator.upload(id: rec.id, content: rec.transcript!,
                                     projectSlug: rec.context.projectSlug)
        }
    }
}
```

- [ ] **Step 2: Call sweep** — in `MainView.onAppear` add `Task { await RetryService(store: store, coordinator: coordinator).sweep() }`.

- [ ] **Step 3: Build, expect success** — build command as before.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat: retry sweep for failed uploads"`

---

### Task 22: Audio retention cleanup

**Files:**
- Create: `App/Capture/AudioRetention.swift`
- Modify: `MainView.onAppear` (run cleanup)

- [ ] **Step 1: Implement**

`App/Capture/AudioRetention.swift`:
```swift
import Foundation
import PRLifeKit

@MainActor
struct AudioRetention {
    let store: SwiftDataCaptureStore
    /// Deletes audio files for captures uploaded > 24h ago; keeps transcript + record.
    func purge(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-24 * 3600)
        for rec in store.all()
            where rec.status == .done && rec.createdAt < cutoff && rec.audioFileName != nil {
            let url = AVAudioRecorderService.capturesDir.appendingPathComponent(rec.audioFileName!)
            try? FileManager.default.removeItem(at: url)
            store.update(id: rec.id) { $0.audioFileName = nil }
        }
    }
}
```

- [ ] **Step 2: Call on launch** — in `MainView.onAppear` add `AudioRetention(store: store).purge()`.

- [ ] **Step 3: Build, expect success.**

- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat: 24h audio retention cleanup after upload"`

---

### Task 23: Empty state + final QA pass

**Files:**
- Modify: `App/Screens/MainView.swift` (empty state)

- [ ] **Step 1: Add empty state** — when `records.isEmpty`, show centered `Text("No captures yet").font(Theme.mono(11)).foregroundStyle(Theme.label)` in place of the list.

- [ ] **Step 2: Run the full kit test suite** — `swift test`
Expected: all green.

- [ ] **Step 3: Build for simulator** — build command as before, expect BUILD SUCCEEDED.

- [ ] **Step 4: Manual device QA checklist** (record results in the commit body):
  - Record in-app; appears in history; transcribes; uploads → `DONE_`.
  - Start, lock phone, keep talking, stop → audio captured full duration.
  - Airplane mode during stop → `FAILED_`; re-enable network, reopen app → retry → `DONE_`.
  - Action Button start while locked → records.
  - Verify the entry shows up in the PR Life web app under today's entries.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: empty state + V1 QA pass"`

---

## Self-Review (completed during planning)

**Spec coverage:**
- On-device transcription + reliable recording → Tasks 8, 9, 14. ✓
- Zero backend data changes / Bearer auth → Tasks 5, 13. ✓
- 7 modules (Theme, AudioRecorder, Transcriber, CaptureStore, LifeAPIClient, CaptureCoordinator, Live Activity/Intents) → Tasks 10–12, 8, 8, 7/14, 5/6, 9, 18–20. ✓
- Main + Devices screens → Tasks 16, 17. ✓
- Lock-screen presence (Live Activity) + lock-screen start (Action Button/Intent) → Tasks 18–20. ✓
- Keychain config, WiFi-only, retry queue → Tasks 15, 6, 21. ✓
- Permissions (mic/speech/background audio) → Task 2 Info.plist. ✓
- Audio retention → Task 22. ✓
- `LIFE_MOBILE_TOKEN` backend change → Task 13. ✓
- Out-of-scope items (Pebble/Watch/widgets/macOS) correctly absent; CaptureCoordinator leaves the seam for hardware. ✓

**Type consistency:** `CaptureStoring`, `AudioRecording`, `Transcribing`, `CaptureCoordinator`, `LifeAPIClient.upload`, `UploadGate`, `PRLifeAction`, `CaptureRecord`, `CaptureStatus`, `CaptureContext` names are used identically across kit, app, tests, and intents.

**Known adaptation risks flagged inline:** `Sendable` on `CaptureStoring` vs `@MainActor` store (Task 14 note); App Intent `openAppWhenRun = true` for reliable audio session (Task 20); on-device-only transcription with no silent cloud fallback (Task 14).
