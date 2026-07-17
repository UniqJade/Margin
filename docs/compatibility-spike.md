# Apple Books compatibility spike

The native trigger is host-dependent. Complete this matrix on every supported OS
generation before calling that platform integration verified.

## Current platform status

| Platform | Status | Meaning |
|---|---|---|
| macOS | **Verified, shortcut path only** | Apple Books selection reached Margin through explicit `Control–Option–M` Accessibility-assisted Copy on the recorded configuration |
| iOS/iPadOS | **Experimental** | App, Action Extension, and App Intent exist structurally, but Apple Books handoff has not been tested on a physical device |

“Verified” applies only to the exact recorded OS, Books version, trigger, and
selection cases. A successful build, registered Service, declared extension, or
working text editor does not verify Apple Books handoff.

## Procedure

Use a DRM-free test book you are allowed to quote. Configure Margin with a valid provider, then perform each case in light mode, dark mode, and full screen.

| Platform / trigger | Selection | Expected handoff | Result to record |
|---|---|---|---|
| macOS Books / `⌃⌥M` | one word | Explicit Copy capture receives exact selected word | OS version, Books version, pass/fail, screenshot |
| macOS Books / `⌃⌥M` | one sentence | Explicit Copy capture receives exact punctuation | OS version, Books version, pass/fail, screenshot |
| macOS Books / `⌃⌥M` | multiline paragraph | Explicit Copy capture receives normalized text ≤2,000 characters | OS version, Books version, pass/fail, screenshot |
| macOS Books / Services | representative text selection | Record whether Books exposes the registered text Service | OS version, Books version, available/unavailable, screenshot |
| iOS/iPadOS Books / Action Extension | one word | Extension receives plain or attributed text | Device, OS version, Books version, pass/fail, screenshot |
| iOS/iPadOS Books / Action Extension | one sentence | Extension receives exact punctuation | Device, OS version, Books version, pass/fail, screenshot |
| iOS/iPadOS Books / Action Extension | multiline paragraph | Extension receives normalized text ≤2,000 characters | Device, OS version, Books version, pass/fail, screenshot |

## Locally discoverable toolchain and host versions

Recorded on 2026-07-13 from installed metadata and command-line tools:

- macOS 26.5 (build 25F71), from `sw_vers`;
- Xcode 26.6 (build 17F113), from `xcodebuild -version`;
- Apple Books 8.5 (build 6570), from `/System/Applications/Books.app/Contents/Info.plist`;
- XcodeGen 2.45.4, from `xcodegen --version`.

## Recorded Mac result

| OS | Books | Services registration | Books handoff | Supported trigger |
|---|---|---|---|---|
| macOS 26.5 (25F71) | 8.5 (6570) | Tested: registered and enabled under Text services | Tested unsupported in this host/version: the Books reading view did not offer enabled text Services for a selected word | Confirmed: select text, then press Control–Option–M (`⌃⌥M`); Margin performs Copy through Accessibility and reads only the newly copied selection |

## Evidence and status boundaries

- **Tested:** macOS Services registration is present in the built app metadata. A selected Apple Books passage can be handed to Margin with Control–Option–M on the recorded Mac configuration; this is the supported Books path for that configuration.
- **Tested unsupported:** direct Services delivery from the Apple Books reading view was not exposed on Apple Books 8.5 / macOS 26.5. Registration alone does not establish host compatibility.
- **Fallback:** when a Mac host does not expose the Service, Control–Option–M uses Accessibility to invoke Copy and consumes only a newly changed clipboard selection.
- **Automated structural evidence only:** the iOS Action Extension declares text activation and contains plain-text and attributed-text handlers. This does not confirm that Apple Books supplies selected text to it.
- **Untested:** iOS/iPadOS Apple Books Action Extension delivery remains a manual acceptance gate for each OS and Books version.

Simulator compilation must be reported as “builds successfully,” not “works in
Apple Books.” Mobile status remains Experimental until a physical-device row is
recorded here.

If iOS/iPadOS opens the action without text, mark the host handoff unsupported for that exact OS/Books combination. Do not add screenshot/OCR capture; use the included **Look Up English Text** App Intent in a pinned Share Sheet Shortcut.
