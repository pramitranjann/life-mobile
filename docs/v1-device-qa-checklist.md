# PR Life iOS v1 — Physical-Device QA Checklist

Everything to date is simulator-built + unit-tested only. These behaviors can ONLY be validated on a real iPhone. Run this before v2 implementation lands. Log each as PASS/FAIL; failures become fix-tasks.

## Prerequisites
- Physical iPhone, iOS 17+.
- Xcode signing: set a Development Team on BOTH targets (`PRLifeMobile`, `PRLifeWidgets`). The **App Group** `group.com.pramitranjan.prlife` and bundle IDs (`com.pramitranjan.prlife`, `.widgets`) must exist on your Apple developer account (Xcode "Automatically manage signing" can create them).
- Backend deployed with `LIFE_MOBILE_TOKEN` set (the `life-mobile-token` branch merged/deployed). In the app's **Devices** screen, set Base URL = your deployed `https://…` and Token = `LIFE_MOBILE_TOKEN`, then Save.
- Build to device: `cd ~/Developer/PRLifeMobile && xcodegen generate`, open `PRLifeMobile.xcodeproj`, pick your device, set signing, Run.

## Checklist
1. **In-app capture loop** — hold RECORD, speak, release → row shows PROCESSING_ then DONE_; the transcribed text appears as a voice entry in the web app `/life` (today).
2. **Background/locked recording** — start recording, lock the phone (or pocket it) for 30–60s while talking, unlock, stop → audio captured for the FULL duration and transcribes. (Validates `.playAndRecord` + `audio` background mode — the core reliability claim.)
3. **Cold Action-Button / Shortcut START while locked** — assign `StartCaptureIntent` to the Action Button (or run from Shortcuts) with the app force-quit + phone locked → a capture actually records. (Validates `openAppWhenRun` + `CaptureEnvironment.shared` cold-init router; the prior nil-bridge risk.)
4. **Live Activity** — during a capture, confirm the recording pill shows on the Lock Screen + Dynamic Island with a running timer, and the interactive **Stop** button actually stops + uploads. (Validates C1 `LiveActivityIntent` + the `CaptureControlChannel` cross-process backstop.)
5. **Deep links** — `prlife://capture?context=work` starts a work capture; `prlife://stop` stops it (test via Shortcuts "Open URL" or Safari).
6. **Offline retry** — airplane mode, do a capture → FAILED_ (transcript preserved); re-enable network, relaunch → launch sweep retries → DONE_.
7. **Permission-denied paths** — deny mic, then (reset & ) deny speech → capture lands as FAILED_ with a sensible message; UI does NOT get stuck showing RECORDING.
8. **On-device Speech** — confirm transcription works for your locale (the app hard-fails by design if `supportsOnDeviceRecognition` is false — verify the language pack is present).
9. **Delete** — delete a capture → removed from the list AND a `DELETE /api/life/entries/:id` removes it server-side (check the web app).
10. **(Optional) 24h retention** — a DONE_ capture older than 24h loses its `.m4a` but keeps its transcript row.

## Report
For each FAIL, note: step #, what happened, any Xcode console error. Bring that list back and each becomes a fix-task before v2 ships.
