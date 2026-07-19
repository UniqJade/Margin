# Changelog

All notable changes to Margin are documented in this file.

The project follows [Semantic Versioning](https://semver.org/) for source
releases. Margin does not currently distribute public application binaries.

## [Unreleased]

## [0.1.2] - 2026-07-19

### Changed

- Natural Translation now leads with the complete Chinese passage and keeps the
  English original inside a collapsed disclosure.
- Semantic Alignment has become Bilingual View: numbered sentence or
  sentence-range cards now separate English and Chinese with clearer hierarchy,
  spacing, and orange navigation markers.
- Copy and Speak use only the Chinese passage in Natural Translation and the
  visible English–Chinese pairs in Bilingual View.
- Results with zero or one alignment block stay in Natural Translation without
  showing a mode switch or a technical alignment warning.
- The standard macOS Settings scene adds **Margin → Settings…** and `⌘,` while
  keeping the menu-bar Settings entry connected to the same window.
- Follow System, Light, and Dark now use one app-wide macOS appearance source,
  preventing title bars and SwiftUI content from retaining opposite themes.
- Provider-returned Chinese uses a conservative local typography pass for
  Chinese quotation marks, full-width punctuation, and stray CJK spacing in
  displayed, copied, spoken, and saved-summary text.
- Chinese passage text keeps its Songti reading face on macOS while applying
  local spacing only after Chinese commas, preventing them from looking like
  inserted spaces without changing the punctuation character itself.
- Apple Books attribution footers such as “Excerpt From … This material may be
  protected by copyright” are removed before translation and from returned or
  previously cached passage results. Legacy cached translations are reused and
  cleaned locally without another provider request.
- Passage panels use the existing page icon beside a clearer Margin wordmark.

### Compatibility

- Structured provider output, cache and saved-data formats, Keychain behavior,
  and permission handling are unchanged. Only recognized terminal Apple Books
  attribution metadata is excluded from selections and passage results.

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

[Unreleased]: https://github.com/UniqJade/Margin/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/UniqJade/Margin/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/UniqJade/Margin/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/UniqJade/Margin/releases/tag/v0.1.0
