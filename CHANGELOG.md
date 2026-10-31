# Changelog

All notable changes to FeedbackKit are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.1] - 2026-10-31

### Changed

- The thank-you screen's glow behind the icon is about half as strong, and the icon's shadow is a soft neutral one rather than tinted.

## [2.0.0] - 2026-10-31

### Changed

- **Breaking:** a successful send now ends on a thank-you screen, in the manner of PaywallKit's: the form fades to the app icon over a drifting backdrop, then the thanks land under it. It stays about 5 seconds, or until tapped, in place of the 1.5 s hold and footer line.
- **Breaking:** `FeedbackView`'s initializers take the `icon` the screen shows.
- **Breaking:** `FeedbackString` has `.thanksRead`, for someone who left no address, and `.thanksMayReply`, for someone who did. `.thanks` is now the screen's title rather than a footer line, so give it copy to match.
- On iOS the email field no longer turns autocorrection off, which took the keyboard's suggestion bar and AutoFill's address with it.

## [1.0.1] - 2026-10-25

### Changed

- The README shows how to send to your own backend with a `FeedbackSender`, and the public API has documentation comments.

## [1.0.0] - 2026-10-25

### Added

- `FeedbackView`: Swiftflip's feedback form as a package, for iOS sheets and macOS sheets or windows. It covers the message and optional email fields, the diagnostics footer, the email check, the Send morph through a spinner to a checkmark, the 1.5 s thank-you hold, the failure alert with Try Again, the offline message, Discard Changes from the close button and from a swipe-down, and the cannot-send state for devices without App Attest.
- The request flow to the HK Softworks feedback service, wire contract v1: AppTransaction, App Attest key generation and registration, `HKF1` assertions, idempotent retries, re-registration on `428`, a new registration challenge on `401`, and one key rotation when DeviceCheck calls a key invalid.
- `FeedbackSender`, `FeedbackSubmission` and `FeedbackError`, so previews, demos and UI tests can drive the form without App Attest.
- `FeedbackString`: every piece of copy, resolved through the app's lookup. The kit ships no strings.
- A demo app with a fake sender, and README screenshots of each state in light and dark mode.
