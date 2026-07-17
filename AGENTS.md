# AGENTS.md — PRLifeMobile

Read PROJECT.md first (live state), and DESIGN.md before any UI work — it is
the native translation of the PR Life web design system and overrides
TASTE.md where it explicitly deviates.

- Build system: `xcodegen` regenerates the .xcodeproj from project.yml; run it
  after adding/removing files. Four targets: PRLifeMobile, PRLifeWidgets,
  PRLifeMac, PRLifeMacWidgets.
- All colors/fonts/shared UI primitives come from PRLifeKit
  (`Sources/PRLifeKit/Theme/`). Never inline hex values or system text fonts.
- Verify with: build both app schemes + `swift test`, then eyeball in the
  simulator — widget and Live Activity chrome regressions don't show up in
  builds.
