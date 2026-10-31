# AGENTS.md

Instructions for agents working in this repository. RFC 2119 keywords apply.

## Package Scope

- This is a Swift package for a reusable SwiftUI feedback form. The supported product surfaces are iOS 26+ and macOS 26+.
- watchOS is out of scope unless the user explicitly asks for it. Every source file MUST stay wrapped in `#if os(iOS) || os(macOS)` (`#if os(iOS)` for UIKit-only files): consumers link the package into frameworks that also build for watchOS.
- The kit owns the form (`FeedbackModel`), the diagnostics, and the whole request flow to the feedback service (`FeedbackClient`): App Attest keys, AppTransaction, challenges, assertions and retries. The consuming app owns only the service URL, its bundle ID, the copy and the presentation.
- The wire contract lives in the feedback service's README (§ "Wire contract (v1)"). It MUST NOT be changed from this side. If the kit needs something the contract does not say, stop and ask.

## SwiftUI Standards

- Use SwiftUI. The one UIKit piece is `SheetDismissalGuard`, which turns a swipe-down on a draft into the discard confirmation; keep it.
- Do not use deprecated APIs such as `foregroundColor`, old `alert` overloads, or `animation(_:)` without `value:`.
- Preserve accessibility in every UI change: VoiceOver labels and announcements, Dynamic Type, Reduce Motion, contrast, and light and dark mode.
- Read Reduce Motion in every view that animates. Reduce Motion turns the button morph, footer changes and thank-you screen into instant swaps, keeps every haptic, and keeps the thank-you screen's time on screen.
- Keep `.accessibilityIdentifier("feedback.form")`. Consumers' UI tests find the form by it.
- Keep public API names, defaults, and initializer behavior stable unless the requested change explicitly requires a breaking change.

## Privacy

- Never log message text, email addresses, AppTransaction JWS values, assertions, attestations or key IDs. Log status codes and error domains and codes only.
- Persistent keys are prefixed with the app's bundle ID. Never hard-code another namespace.

## Localization

- The kit ships no copy. Every user-visible or spoken string MUST come from a `FeedbackString` case through the app's lookup. Never write a literal in `Text`, a label, a hint or an alert.
- New copy is a new `FeedbackString` case, which is a breaking change: apps switch over the enum exhaustively. Update the README's reference `switch` and the demo app with it.

## Testing and Verification

- Add or update Swift Testing coverage for every behavior change. `FeedbackModelTests` drives the model with a fake `FeedbackSender` and a recorded `sleep`; `FeedbackClientTests` drives the client with a fake transport and a fake App Attest service.
- Tests MUST compare `FeedbackString` values, never English literals.
- Run `swift test` and `xcodebuild -scheme FeedbackKit -destination 'generic/platform=iOS Simulator' build` before calling work complete, and `git diff --check` before committing.
- CI (`.github/workflows/ci.yml`) runs macOS and iOS Simulator tests on Xcode 26.6 and 27.0 and builds the demo app. Keep it green.

## Documentation and Releases

- Keep README examples compiling against the public API. The demo app's `feedbackText` is the README's reference `switch`; keep them identical.
- Record every public API or behavior change under `## [Unreleased]` in `CHANGELOG.md`.
- Releases are annotated SemVer tags without a `v` prefix (`1.0.1`). Never move a published tag.
- Use semantic commit messages: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, `ci:`.
