# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.1/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.3] - 2026-07-08

### Fixed

- Align the package homepage metadata with the project landing page.
- Correct the build commands shown in the README to reflect the universal, signed builds.

## [0.0.2] - 2026-07-08

### Changed

- Pin `swift-argument-parser` to 1.8.2 so builds resolve a fixed dependency version.

## [0.0.1] - 2026-07-08

### Added

- `tcc-preapprove`, a Swift command-line tool to inspect and manage macOS TCC grants for a binary
  or app.
- `grant` subcommand to write an allow row with a generated code-signing requirement blob.
- `revoke` subcommand to delete access rows for a client.
- `list` subcommand to print existing access rows.
- `profile` subcommand to emit a PPPC `.mobileconfig` for MDM distribution, which needs neither SIP
  disabled nor Full Disk Access.
- `--version` flag.
- Universal (arm64 and x86-64) release binary, signed with the required TCC entitlements and
  published on each tag.
