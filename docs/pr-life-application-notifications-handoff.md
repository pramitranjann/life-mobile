# PR Life Application Notifications — PRLifeMobile Handover

**Date:** 2026-07-16
**Status:** Backend implemented; native macOS/iOS delivery remains
**Repos:** `~/portfolio` (PR Life backend) and `~/Developer/PRLifeMobile` (native clients)

## Outcome

PR Life now checks four ambassador/student-program pages from its existing daily cron. When a tracked program changes to an actionable state (`open` or `date_announced`), the backend:

1. writes one durable `life_notifications` record;
2. deduplicates that alert by program + observed status hash;
3. sends the alert through the existing Resend email channel; and
4. exposes the same alert to PRLifeMobile through an authenticated API.

The first successful check establishes a baseline and does **not** notify. Later unchanged checks do not notify again.

## Programs and verified baseline

| Key | Program | URL | Expected baseline on 2026-07-16 |
|---|---|---|---|
| `claude-campus-ambassador` | Claude Campus Ambassador | `https://claude.com/programs/campus` | `closed` |
| `claude-builder-club` | Claude Builder Club | `https://claude.com/programs/campus` | `no_window` |
| `codex-ambassadors` | Codex Ambassadors | `https://developers.openai.com/community/codex-ambassadors` | `paused` |
| `openai-campus-network` | OpenAI Campus Network | `https://openai.com/index/openai-campus-network-student-club-interest-form/` | `rolling_interest` |

The OpenAI Campus Network interest form is deliberately not treated as a newly opened cohort. It becomes actionable only if the tracked page gains explicit application-open language or a dated cohort/application announcement.

## Backend implementation already present

- `~/portfolio/lib/life/program-application-monitor.ts`
  - Four program-specific inspectors run on one shared schedule.
  - Reuses a page fetch when two programs share the Claude Campus URL.
  - Stores a normalized status excerpt and SHA-256 status hash.
  - Treats `open` and `date_announced` as actionable.
  - Is failure-isolated so a source outage does not break the rest of the daily PR Life cron.
- `~/portfolio/app/api/life/cron/daily/route.ts`
  - Starts `runProgramApplicationChecks()` alongside the existing daily work.
- `~/portfolio/lib/life/notifications.ts`
  - Creates deduplicated notifications and provides query/read-state helpers.
- `~/portfolio/app/api/life/notifications/route.ts`
  - Native notification feed.
- `~/portfolio/app/api/life/notifications/[notificationId]/route.ts`
  - Read/unread state endpoint.
- `~/portfolio/supabase/migrations/009_program_application_notifications.sql`
  - Adds `program_application_monitors` and `life_notifications`.

### Required backend rollout order

1. Apply migration `009_program_application_notifications.sql` to the production Supabase project.
2. Deploy the portfolio app.
3. Invoke the daily cron once with the cron bearer token, or wait for the next scheduled run.
4. Confirm four baseline rows exist in `program_application_monitors`.
5. Confirm the baseline run created no `program_application` notification.

The existing Vercel schedule is `30 14 * * *` (14:30 UTC, 22:30 in Malaysia). This satisfies the requested 12–24 hour cadence.

## Native API contract

Authentication is unchanged:

```http
Authorization: Bearer <LIFE_MOBILE_TOKEN>
```

The base URL and token must continue to come from `KeychainConfig` through `LifeAPIClient.configurationProvider`.

### Fetch notifications

```http
GET /api/life/notifications?after=2026-07-16T00:00:00.000Z&limit=50
```

Optional query parameters:

- `after`: strict ISO-8601 lower bound on `created_at`;
- `unread=true`: global read-state filter; and
- `limit`: clamped by the server to 1–100, default 50.

Response:

```json
{
  "notifications": [
    {
      "id": "uuid",
      "user_id": "owner",
      "kind": "program_application",
      "title": "Codex Ambassadors applications are open",
      "body": "Applications are now open ...",
      "url": "https://developers.openai.com/community/codex-ambassadors",
      "metadata": {
        "programKey": "codex-ambassadors",
        "programName": "Codex Ambassadors",
        "status": "open",
        "statusHash": "sha256"
      },
      "dedupe_key": "program-application:codex-ambassadors:sha256",
      "created_at": "2026-07-16T14:30:00.000Z",
      "read_at": null
    }
  ]
}
```

### Mark read/unread

```http
PATCH /api/life/notifications/<notification-id>
Content-Type: application/json

{ "read": true }
```

Response: `{ "notification": <updated notification> }`.

Read state is global across PR Life. Do **not** use `unread=true` as the native delivery cursor: if macOS marks an alert read, iOS would otherwise miss it. Each native installation must keep its own `after` cursor.

## Native implementation plan

### 1. Add the shared API model

Add `Sources/PRLifeKit/Model/LifeNotification.swift`:

```swift
public struct LifeNotification: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let body: String
    public let url: URL?
    public let metadata: [String: String]
    public let createdAt: Date
    public let readAt: Date?
}
```

Use explicit `CodingKeys` for `created_at` / `read_at`. If `[String: String]` proves too narrow for future JSON metadata, add a dedicated `LifeNotificationMetadata` struct instead of an untyped `Any` dictionary.

### 2. Extend `LifeAPIClient`

Add:

```swift
public func fetchNotifications(after: Date?, limit: Int = 50) async throws -> [LifeNotification]
public func setNotificationRead(id: String, read: Bool) async throws -> LifeNotification
```

Follow the existing `fetchEvents` / `fetchTasks` implementation:

- resolve `configurationProvider` on every request;
- use `validConfiguration()`;
- send the same Bearer header;
- use `URLComponents` for `after` and `limit`;
- decode dates with an ISO-8601 strategy that accepts fractional seconds; and
- use the existing `validate(_:_:)` path for non-2xx responses.

Add `MockURLProtocol` request/decoding coverage next to `LifeAPIReadsTests`.

### 3. Add a per-installation delivery cursor

Store the newest delivered `created_at` in app-local `UserDefaults`, with separate keys per target, for example:

- iOS: `lifeNotifications.lastDeliveredAt.ios`
- macOS: `lifeNotifications.lastDeliveredAt.mac`

Delivery algorithm:

1. Fetch with `after=<local cursor>` and no `unread` filter.
2. Sort oldest to newest before presenting.
3. Only present `kind == "program_application"` in this first implementation.
4. Schedule a local notification using the server notification UUID as the local identifier.
5. Advance the cursor only after every item up to that timestamp has been scheduled successfully.

On the first native sync, fetch the latest page and deliver only `program_application` notifications created in the previous 24 hours, then save the newest timestamp. This avoids replaying an old notification history on a newly installed client without missing a recently opened application.

### 4. Present local notifications

Use `UserNotifications` in both app targets.

- Request `.alert`, `.badge`, and `.sound` authorization after the first successful authenticated notification fetch.
- Set `UNUserNotificationCenter.current().delegate` to a long-lived object.
- In `willPresent`, return banner + sound so an alert is visible even while PRLifeMobile is foregrounded.
- Use `UNMutableNotificationContent`:
  - title = server `title`;
  - body = server `body`;
  - sound = `.default`;
  - category identifier = `PRLIFE_PROGRAM_APPLICATION`;
  - `userInfo["url"]` = server URL.
- On notification response, open the program URL.

Local notifications require user authorization but no Push Notifications entitlement or APNs certificate.

### 5. Wire macOS lifecycle

`MacApp/Sync/LifeSyncService.swift` already refreshes on launch and every 15 minutes. Add notification polling to that service or inject a dedicated `LifeNotificationService` and call it from the same refresh cycle.

Required triggers:

- launch (`startPeriodicRefresh()` already performs an immediate refresh);
- every 15-minute periodic refresh;
- menu-bar popover `.task` refresh; and
- manual Sync Now.

Keep notification-fetch failure separate from event/task snapshot state: a temporary notification API failure must not make the Today dashboard appear disconnected if events and tasks synced successfully.

### 6. Wire iOS lifecycle

`App/PRLifeMobileApp.swift` currently has no server-read lifecycle service. Add a `@StateObject` notification service at the app root and observe `scenePhase`.

Required triggers:

- initial `WindowGroup` task; and
- every transition to `.active`.

Do not add a permanent rapid background timer. iOS may suspend it, and the backend only checks once daily. True delivery while the app is terminated requires APNs (see below).

## Important delivery boundary

This handover’s native implementation is authenticated polling plus local notifications. It guarantees native alerts when either app launches/returns active and, on macOS, during the existing 15-minute running-app refresh. Email remains the immediate out-of-app delivery channel after the server cron detects a change.

If native alerts must arrive while iOS is terminated and the Mac app is not running, add APNs as a separate phase:

1. register per-device APNs tokens in PR Life;
2. store environment/platform/token records server-side;
3. send APNs from the backend when `createLifeNotification` succeeds;
4. add the Push Notifications capability and `aps-environment` entitlement; and
5. handle token rotation, invalid-token cleanup, and notification taps.

Do not attempt to solve terminated-app delivery with a timer or BackgroundTasks alone; iOS does not guarantee execution at the time the daily cron fires.

## Verification gates

### Shared/API tests

- Authorized `GET /api/life/notifications` request shape.
- `after` timestamp encoding and limit.
- Fractional and non-fractional ISO-8601 decoding.
- Notification metadata decoding.
- Authorized `PATCH` read-state request.
- 401 / malformed response maps through existing `LifeAPIError` behavior.

### Coordinator tests

- Same server UUID is not delivered twice.
- Two notifications are presented oldest-first.
- Cursor advances only after successful scheduling.
- macOS and iOS cursors are independent.
- A Mac read-state update cannot suppress iOS delivery.

### Build and manual QA

```sh
swift test
xcodebuild -scheme PRLifeMac -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/prlife-mac-build build
xcodebuild -scheme PRLifeMobile -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/prlife-ios-build build
```

Manual QA must cover notification permission denied/allowed, foreground banners, app relaunch deduplication, URL tap-through, expired token behavior, and one device marking an alert read before the other device syncs.

## Definition of done

- Both native targets fetch the new API with `LIFE_MOBILE_TOKEN`.
- Both request notification permission and show a foreground banner + sound.
- macOS checks on launch, periodic refresh, popover refresh, and manual sync.
- iOS checks on launch and every foreground transition.
- Each installation deduplicates with its own persisted cursor.
- Tapping an alert opens the official program page.
- All shared tests and both native builds pass.
- The production database migration and four baseline monitor rows are verified.
