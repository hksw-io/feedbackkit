# Changelog

All notable changes to FeedbackKit are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `CrashReporter` takes the crash reports MetricKit hands the app on the launch after a crash and sends them to the HK Softworks feedback service's `POST /v1/crash`, only when the person agrees. Start it as the app launches. It reads `MetricManager` on iOS and macOS 27 and `MXMetricManager` before, and does nothing without App Attest, so on a Mac before macOS 27 and in the Simulator.
- `CrashReportView` asks whether to send: Send, Always Send and Don't Send, none of them the default, with a link to the app's privacy policy. Swiping it down or pressing Escape is Don't Send. Its copy comes from the new `CrashReportString`, so apps that switch over `FeedbackString` don't change.
- `alwaysSends` keeps Always Send in `UserDefaults` under `<bundle ID>.feedbackKit.alwaysSendCrashReports`, for a switch that turns it off.
- A report holds the crashed run's version, system and device, the exception and signal, an Objective-C exception's name and class, and the crashed thread's frames, at most 512. Never an exception's message or arguments, which can hold what someone typed. A stack too deep for Foundation's JSON reader, such as from runaway recursion, is still read.
- A privacy manifest declaring Crash Data, not linked and not used for tracking, and the kit's use of `UserDefaults`.

## [1.2.0] - 2026-11-11

### Changed

- **Breaking:** `FeedbackString` has `.messageTooLong`, the notice under a message of more than 5,000 characters. An app updating from 1.1 has to add it to its `switch`.
- **Breaking:** `FeedbackString` has `.sending`, the VoiceOver label of the Send button's spinner, which had none. Add it to the `switch` too.
- A message longer than 5,000 characters is no longer cut without a word. It stays as typed, Send is disabled, and the message's footer, which VoiceOver also speaks, says it is too long until it is shortened.
- Both fields are disabled while sending and after a successful send, so a late edit can't make the thank-you screen promise a reply to an address that was never sent.
- The Send button's morph follows the send's state directly. A send that ends inside the 0.2 s fade to the spinner now goes straight on to the checkmark rather than waiting for the fade.

### Fixed

- On iOS, VoiceOver now follows the Send button through a send. A label on the button itself had been overriding the checkmark's `.complete` with `.send`; it is gone, and VoiceOver speaks `.sending` when the send starts and `.complete` when it ends.
- A stalled send no longer holds the form for minutes. Each request to the feedback service fails after 15 seconds without an answer, and Cancel (the close button on iOS) is disabled while sending rather than doing nothing when tapped.
- A service outage no longer reads as "You're offline". A timeout, or a host that can't be found or reached, now ends in `.failed` and is logged; `.offline` is kept for no connection, a lost connection, and cellular data or roaming being off.
- When the service has forgotten the App Attest key (`428`), or rejects a registration challenge (`401`), the kit now generates a new key straight away. DeviceCheck attests a key only once, so attesting the old key again failed with `invalidKey` and recovery only worked through the one key rotation, after a wasted challenge.

## [1.1.0] - 2026-10-31

### Changed

- A successful send now ends on a thank-you screen, in the manner of PaywallKit's: the form fades to the app icon over a drifting backdrop, then the thanks land under it. It stays about 5 seconds, or until tapped, in place of the 1.5 s hold and footer line.
- `FeedbackView`'s initializers take the `icon` the screen shows. An app updating from 1.0 has to pass one.
- `FeedbackString` has `.thanksRead`, for someone who left no address, and `.thanksMayReply`, for someone who did. An app updating from 1.0 has to add both to its `switch`. `.thanks` is now the screen's title rather than a footer line, so give it copy to match.
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
