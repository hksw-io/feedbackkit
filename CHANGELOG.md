# Changelog

All notable changes to FeedbackKit are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[semantic versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-10-25

### Added

- `FeedbackView`: Swiftflip's feedback form as a package, for iOS sheets and macOS sheets or windows. It covers the message and optional email fields, the diagnostics footer, the email check, the Send morph through a spinner to a checkmark, the 1.5 s thank-you hold, the failure alert with Try Again, the offline message, Discard Changes from the close button and from a swipe-down, and the cannot-send state for devices without App Attest.
- The request flow to the HK Softworks feedback service, wire contract v1: AppTransaction, App Attest key generation and registration, `HKF1` assertions, idempotent retries, re-registration on `428`, a new registration challenge on `401`, and one key rotation when DeviceCheck calls a key invalid.
- `FeedbackSender`, `FeedbackSubmission` and `FeedbackError`, so previews, demos and UI tests can drive the form without App Attest.
- `FeedbackString`: every piece of copy, resolved through the app's lookup. The kit ships no strings.
- A demo app with a fake sender, and README screenshots of each state in light and dark mode.
