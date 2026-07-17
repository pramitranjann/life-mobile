---
project: PRLifeMobile (PR Life native companions)
status: building
platforms: [ios, macos, widgets]
tokens: Sources/PRLifeKit/Theme/PRLifeTokens.swift (bridged in PRLifeTheme.swift)
figma: none
updated: 2026-07-17
---

# DESIGN.md — PR Life native

Inherits ~/agent-system/core/TASTE.md. Only deviations and specifics below.

## Intent
Dark instrument panel: near-black ground, DM Mono everywhere, one red accent
that means "live or actionable". The canonical design is the **web app**
(`~/portfolio/app/globals.css`, `.life-shell`) — native surfaces translate it,
never reinterpret it. The signature move: hard rectangles + uppercase mono
labels with a trailing underscore (`CAPTURES_`).

## Source of truth
| Area | Lives in | Wins conflicts |
|---|---|---|
| Design language | `~/portfolio/app/globals.css` `.life-shell` | web CSS |
| Native tokens | `Sources/PRLifeKit/Theme/PRLifeTokens.swift` | must mirror web CSS |
| SwiftUI bridge + shared views | `Sources/PRLifeKit/Theme/PRLifeTheme.swift` | code |
| Shipped native screens | the code | code |

## Tokens
**Color:** all in `PRLifeTokens.Color` — bg/panel/panel2/mutedBG/border/
hairline/divider/text/muted/label/transcript + accent/green/amber/danger.
Never inline a hex in a view file. Accent = interactive or live state, never
decoration. Muted-content floor is `label` (#6F6F6F) — nothing dimmer.
**Accent alphas:** exactly two — `Alpha.accentSoft` (0.10, hover/live-soft
fills) and `Alpha.accentLine` (0.35, secondary outlines). Don't invent more.
**Type:** DM Mono is the default for ALL text (`Theme.mono`; `Theme.body`
aliases it). Clash Display (`Theme.display`) only for big headings/titles.
Scale: 10 floor (non-tappable micro), 11 labels/meta/errors, 12 buttons-
compact, 13 buttons/content, 14 brand, 16 text inputs (iOS zoom rule),
18–22 display. Nothing tappable below 11. Eyebrow labels: 11 + tracking 1.7.
**Spacing:** 4/8 grid, dense; 13–16px row padding, 20px page gutter.
**Radius:** zero. Rectangles only — except circles: TaskCheckbox, dots.
**Depth:** 1px borders (`border` for controls, `hairline` for rows/dividers)
+ panel background shifts. No shadows anywhere in native.
**Motion:** 120–200ms ease-out; `.pressable` opacity dip on every custom
button; recording dot pulses 0.6s (gated on `accessibilityReduceMotion`).
Data never animates.

## Layout
iOS: single column, full-bleed rows, 14–20px gutters. Mac: 340pt popover;
dashboard window min 520pt with top nav tabs. Widgets: small = single fact,
medium = events|tasks split, large = stacked sections + action row.

## Components (all in PRLifeKit unless noted)
| Component | Lives in | The rule |
|---|---|---|
| Theme | PRLifeKit/Theme | the ONLY color/font source; both apps + all widgets |
| TaskCheckbox | PRLifeKit/Theme | circle, 1.5px border, accent fill + dark check when done — never a square |
| PriorityDot | PRLifeKit/Theme | 7px; high=danger, medium=amber, low=label |
| `.pressable` | PRLifeKit/Theme | replaces `.plain` on every custom-drawn button |
| SectionLabel | App + MacApp | uppercase mono 11, tracking 1.7, trailing `_` |
| RecordButton | App/Theme/Components | idle = accent outline; recording = SOLID accent + dark text (only solid-accent surface besides Live Activity STOP) |
| CaptureModePicker / QuickTextModeControl | App / MacApp | segmented = neutral: mutedBG container, active gets panel2 + text — never accent |
| LifeFormatting | PRLifeKit/Widgets | all date/countdown strings; don't hand-roll DateFormatters in views |

## Screen patterns
- Lists are hairline-separated rows, never cards.
- Primary action = accent text + full accent 1px outline, transparent bg.
  Secondary/utility = accent text + `accentLine` outline. Solid accent fill
  = live/recording state only.
- Widget buttons/links always `.buttonStyle(.plain)` wrapped in our own
  square chrome — the system's tinted capsule is an instant fail.
- Empty states: one mono 13 sentence in `label`, no debug strings in release.

## Interaction
- Press: `.pressable` (0.55 opacity, 120ms). Mac hover: accentSoft fill on
  primaries, color shift on links.
- Whole rows toggle their control (settings rows), 44pt targets on iOS.
- Hold-to-record on the RecordButton; VoiceOver gets a toggle activate action.

## Blacklist additions
- No `RoundedRectangle` (any radius), no `.borderedProminent`, no system
  blue anywhere.
- No SF/system font for text — if it's not `Theme.mono/display`, it's wrong
  (SF Symbols icons are fine).
- No new grays: if a shade isn't in PRLifeTokens, it doesn't exist.
- No solid-accent buttons for non-live actions.
- Voice: iOS speaks `UPPERCASE_` for actions; Mac buttons are sentence case
  (platform convention) but section labels stay `UPPERCASE_` on both.
