# Apple Books compatibility spike

The native trigger is host-dependent. Complete this matrix on every supported OS
generation before calling that platform integration verified.

## Current platform status

| Platform | Status | Meaning |
|---|---|---|
| macOS | **Verified, shortcut path only** | Apple Books selection reached Margin through explicit `Control–Option–M` Accessibility-assisted Copy on the recorded configuration |
| iOS/iPadOS | **Tested unsupported on the recorded configuration** | Apple Books exposed neither Margin's Action Extension nor a selected-text Share Sheet Shortcut, so no one-action handoff was available |

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

## Recorded iPad result

Recorded on 2026-07-18:

| Device | OS | Books | Control host | Apple Books Action Extension | Apple Books Shortcut input | One-action status |
|---|---|---|---|---|---|---|
| iPad (9th generation) | iPadOS 26.5 (23F77) | 8.5 | Notes displayed **Look Up with Margin** | Not exposed for a selected passage | Not exposed; the Books action list offered Copy but not the configured selected-text Shortcut | **Unsupported on this configuration** |

Because Apple Books did not expose either trigger, word, sentence, and multiline
payload accuracy could not be tested: every case failed at the host-availability
gate before Margin could receive text. The Notes control confirms that the
extension was installed and registered; it does not establish Books
compatibility.

## Evidence and status boundaries

- **Tested:** macOS Services registration is present in the built app metadata. A selected Apple Books passage can be handed to Margin with Control–Option–M on the recorded Mac configuration; this is the supported Books path for that configuration.
- **Tested unsupported:** direct Services delivery from the Apple Books reading view was not exposed on Apple Books 8.5 / macOS 26.5. Registration alone does not establish host compatibility.
- **Fallback:** when a Mac host does not expose the Service, Control–Option–M uses Accessibility to invoke Copy and consumes only a newly changed clipboard selection.
- **Tested unsupported on the recorded iPad:** Apple Books exposed neither the installed text Action Extension nor the selected-text Shortcut. No direct payload reached Margin.
- **Control evidence:** Notes exposed the same Action Extension, separating Apple Books host behavior from installation or registration failure.
- **Rejected fallback:** copy-then-run clipboard lookup is technically possible but violates the one-action, stay-on-the-page acceptance criterion and is not a supported Margin workflow.

Simulator compilation must be reported as “builds successfully,” not “works in
Apple Books.” The recorded failure is configuration-specific; a future iOS,
iPadOS, or Books version requires a new physical-device matrix before its status
changes. Do not add clipboard, screenshot, or OCR capture as a claimed one-action
fallback.
