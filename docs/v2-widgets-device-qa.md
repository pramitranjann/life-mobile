# PR Life iOS V2 (Upcoming Widget) — Device QA + Release Notes

V2 builds, installs, and unit-tests pass (44/44) on the simulator, but the widget's live behavior and the shared Keychain can only be validated on a **physical iPhone** with a configured `LIFE_MOBILE_TOKEN`. The simulator keychain is permissive and ignores access-group entitlement mismatches, so the items below genuinely only verify on-device.

## ⚠️ Upgrade regression to note in any release (review finding I1)
The shared-Keychain change moved the API base URL + token into a keychain **access group**. After upgrading in place, the app will **not** find the token written by a pre-V2 build, so **capture upload silently stops working until you re-enter Base URL + Token in the Devices screen** (which re-saves them into the shared group). This is by design (spec §83) but is a silent regression of V1 capture-upload — surface it to the user (release note or a one-time in-app hint).

## Device QA checklist
1. **Shared-Keychain read across the app/widget boundary** — set Base URL + Token in the app's Devices screen, add the Upcoming widget; it should show **live** events/tasks (not the "Set up in the app" placeholder). If it stays on the placeholder, the access-group/team-prefix (`8QBV8WL699`, hardcoded — review finding I2) doesn't match on this device.
2. **In-place upgrade (I1)** — install a pre-V2 build, save a token, install V2 over it: confirm capture upload requires a re-save, and the widget prompts setup until then.
3. **Container background (fixed C1)** — confirm small/medium/large render on the dark `Theme.bg`, not the system default.
4. **Live data + refresh** — confirm the timeline refreshes (~30 min `.after` policy) and the post-capture `WidgetCenter.reloadTimelines(ofKind:"PRLifeUpcoming")` visibly updates the widget.
5. **Lock-screen accessory families** — `accessoryRectangular` + `accessoryInline` legibility on the actual Lock Screen.
6. **States** — kill connectivity → `.failed` (empty → setup placeholder); clear config → not-configured placeholder.
7. **Time display (M1 fixed)** — event times respect the device 12/24-hour setting and render in the expected timezone.

## Known follow-ups (non-blocking)
- I2: `KeychainConfig` hardcodes team prefix `8QBV8WL699`; breaks silently (degrades to nil) if the signing team changes.
- Selector test gaps: nil-`start` event drop + within-priority stability are correct but untested.
