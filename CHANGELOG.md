# Changelog

All notable changes to Margin are documented in this file.

The project follows [Semantic Versioning](https://semver.org/) for source
releases. Margin does not currently distribute public application binaries.

## [Unreleased]

## [0.1.1] - 2026-07-18

### Changed

- Passage results now show the Natural Translation view without a redundant
  mode switch when structured alignment contains only one block.
- The Semantic Alignment switch remains available when two or more alignment
  blocks provide a meaningful sentence-level comparison.
- XcodeGen no longer rewrites the checked-in project when the repository is
  cloned into a directory whose name differs from the original checkout.

### Maintenance

- Updated the public CI checkout action to `actions/checkout@v7` after the full
  macOS and iOS validation workflow passed.

## [0.1.0] - 2026-07-17

### Added

- A verified macOS Apple Books workflow: select English text and press `⌃⌥M`.
- Natural English-to-Simplified-Chinese passage translation focused on prose.
- Sentence-level semantic alignment using the same Chinese wording as the
  natural translation.
- Dictionary-style word results with pronunciation, part-of-speech navigation,
  contextual senses, and bilingual examples.
- Follow System, Light, and Dark appearances with English and Simplified Chinese
  interface localization.
- Explicitly saved local items, a bounded local response cache, and device-only
  Keychain storage for a user-supplied provider key.
- Experimental iPhone/iPad container app, Action Extension, and App Intent.
- A local, no-network blind evaluation tool and a documented 40-passage v0.1.0
  evaluation.

### Security and privacy

- Requests contain the selected text rather than book, author, page, or
  surrounding-text metadata.
- Provider response bodies and credentials are excluded from application logs.
- Public-repository checks reject tracked credentials, signing material,
  private evaluation artifacts, and oversized files.

### Known limitations

- Source-only personal build; no public app, DMG, TestFlight build, or hosted
  service.
- English to Simplified Chinese only, with a cloud connection required.
- Direct client-side BYOK is prototype-grade and is not suitable for a public
  binary.
- Semantic alignment is sentence-level. A long selection containing one
  grammatical sentence can produce one alignment block that looks similar to
  Natural Translation.
- iPhone/iPad Apple Books selection delivery remains unverified on physical
  devices.

[Unreleased]: https://github.com/UniqJade/Margin/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/UniqJade/Margin/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/UniqJade/Margin/releases/tag/v0.1.0
