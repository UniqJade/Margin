# Dictionary Popover and Single-Window Design

Date: 2026-07-12
Status: approved design, pending implementation plan

## Objective

Make Margin behave like a temporary Apple Books lookup surface rather than a small translator window. A word lookup should provide a complete, scrollable bilingual dictionary entry, while sentence and passage lookup should remain a concise natural translation. Every lookup trigger must reuse one floating panel; Margin must never show both a normal lookup window and a floating lookup panel.

## Confirmed Decisions

- Word results use the comfortable-density layout shown in the approved visual prototype, approximately 540 × 620 points.
- A word entry shows all common parts of speech in one scrollable document.
- The fixed part-of-speech navigation (`adj.`, `n.`, `v.`, and similar labels) uses anchors: selecting a label scrolls the document to that section rather than replacing the content.
- Each sense places the English definition and Simplified Chinese rendering in the same paragraph, followed by bilingual examples.
- Sentence and passage lookup keeps the existing natural-translation presentation and does not use dictionary sections.
- The lookup panel dismisses when the user presses Escape or returns focus to Apple Books.
- Settings and History remain independent normal windows.

## Scope

### In scope

- Eliminate the duplicate lookup-window lifecycle.
- Add a richer structured word-result model grouped by part of speech.
- Add backward decoding for existing cached and historical word results.
- Update cloud prompts, JSON schema, validation, and repair behavior for the richer model.
- Build an Apple-inspired macOS dictionary panel with fixed header, fixed part-of-speech navigation, scrollable senses, and fixed actions.
- Preserve the existing passage-result model and visual treatment.
- Keep copy, speak, save, retry, and dismiss actions.

### Out of scope

- Scraping or redistributing a commercial dictionary.
- Screenshot or OCR capture.
- Word inflection tables, etymology, thesaurus graphs, images, or offline dictionary data.
- Pixel-for-pixel reproduction of Apple Dictionary.
- iCloud synchronization or accounts.
- Changing the current English-to-Simplified-Chinese language direction.

## Window Architecture

The existing duplicate is caused by two separate lookup surfaces:

1. SwiftUI automatically creates `Window("Margin", id: "lookup")`.
2. `LookupPanelController` separately creates an `NSPanel` for shortcut and Service lookups.

The macOS app will have exactly one lookup surface: the reusable AppKit `NSPanel` managed by `LookupPanelController`. The SwiftUI `Window("Margin", id: "lookup")` scene will be removed. `MenuBarExtra`, Settings, and History remain SwiftUI scenes.

All lookup entry points route to the same controller:

- Control–Option–M
- the menu-bar “Look up text…” action
- a compatible macOS Service
- reopening Margin from the Dock

The controller creates its panel lazily, then reuses the same instance for the process lifetime. A new request replaces the existing selection and phase rather than creating a new window.

The panel will:

- use an approximately 540 × 620 point default content size;
- position itself near the current mouse location while remaining fully inside the visible screen frame;
- fall back to centering on the active screen when a suitable pointer position is unavailable;
- join all Spaces and appear beside full-screen Books;
- hide when the app deactivates or the user presses Escape;
- remain reusable after hiding rather than being released.

Settings and History use their existing independent windows. They do not share the lookup panel lifecycle.

## Word Result Model

`WordLookupResult` evolves from one optional part of speech and a flat string array into a structured dictionary entry:

```swift
struct WordLookupResult {
    let headword: String
    let pronunciations: [WordPronunciation]
    let partsOfSpeech: [WordPartOfSpeech]
    let alternatives: [String]
}

struct WordPronunciation {
    let region: String?       // for example, "BrE" or "AmE"
    let ipa: String
}

struct WordPartOfSpeech {
    let name: String          // for example, "adjective"
    let senses: [WordSense]
}

struct WordSense {
    let contextLabel: String?
    let englishDefinition: String? // optional only for migrated legacy records
    let chineseDefinition: String
    let examples: [WordExample]
}

struct WordExample {
    let english: String
    let chinese: String
    let highlightedPhrase: String?
}
```

Validation limits a result to:

- 1–2 pronunciations;
- 1–3 common parts of speech;
- 1–3 senses per part of speech;
- 0–2 examples per sense.

Every part of speech must have at least one valid sense. Newly returned English and Chinese definitions must be nonempty; only migrated legacy records may omit the English definition. A highlighted phrase is used only when it is a case-insensitive substring of the English example; otherwise the UI renders the example without emphasis.

Part-of-speech abbreviations are derived locally (`adjective` → `adj.`, `noun` → `n.`, `verb` → `v.`) so the model does not control navigation labels. Unknown names use a sanitized short label and remain accessible by their full name.

## Backward Compatibility

Existing cache and history files contain the original word structure. Custom decoding will accept both formats.

For a legacy result:

- the original `partOfSpeech`, or `word` when absent, becomes one `WordPartOfSpeech`;
- each legacy sense becomes a `WordSense` with the legacy text as `chineseDefinition`;
- `englishDefinition` is absent when the old record has no English definition, and the UI renders only its Chinese definition;
- the legacy example and translation become one bilingual `WordExample`;
- the original IPA becomes one pronunciation with no region.

New results encode only the new format. Passage records require no migration.

## Provider Contract

The system prompt continues to treat selected book text as quoted data and ignores embedded instructions. For word requests it asks for dictionary-style structured output with common parts of speech, concise English definitions, natural Chinese definitions, and contextual examples.

The OpenAI JSON schema and DeepSeek JSON-object instructions will describe the same new contract. The word-response token ceiling may increase to approximately 1,600 tokens to accommodate multiple parts of speech; passage requests retain their existing smaller response budget.

Malformed structured output receives the existing single constrained repair attempt. Repair cannot add surrounding book text, metadata, or new instructions. A response that remains invalid maps to a user-facing provider error without displaying or logging the raw response.

## Visual System

The design is Apple-inspired but remains recognizably Margin.

- **Canvas:** near-white system material that adapts to light and dark mode.
- **Primary text:** system label color, approximately charcoal in light mode.
- **Secondary/context text:** system secondary and tertiary label colors.
- **Accent:** restrained Margin blue used only for the active part-of-speech indicator and keyboard focus.
- **Headword:** system serif/New York where available, with a platform serif fallback.
- **Definitions and Chinese:** system sans-serif with PingFang SC fallback.
- **Utility labels:** system caption style with modest tracking.

The characteristic element is the bilingual sense paragraph: a muted context label, English explanation, and immediately adjacent Chinese explanation. Examples sit below as bullets; the model-provided collocation is bold only after substring validation.

## Word Panel Layout

The panel is divided into three stable regions:

1. **Fixed header**
   - headword;
   - one or two IPA pronunciations with optional region labels;
   - close control.
2. **Fixed part-of-speech navigation**
   - abbreviated anchors in document order;
   - active section indicated by a thin blue underline;
   - clicking an anchor performs a reduced-motion-aware scroll to its section.
3. **Scrollable body and fixed footer**
   - numbered senses grouped under full part-of-speech headings;
   - inline bilingual definitions;
   - bilingual bullet examples with validated collocation emphasis;
   - copy, speak, save, and retry actions in a quiet bottom toolbar.

The active anchor updates as the user scrolls. VoiceOver exposes full part-of-speech names, sense numbers, and action labels. Keyboard focus is visible. Reduced Motion disables animated anchor scrolling.

## Passage Panel Layout

Passage results keep the existing natural Chinese translation, optional nuance note, optional literal disclosure, and actions. They use the same single `NSPanel` and dismissal behavior but do not show pronunciation or part-of-speech navigation.

## Loading, Failure, and Empty States

- Loading uses a skeleton that occupies the final header, navigation, and sense layout so the panel does not jump in size.
- The selected word or passage remains available during loading and failure.
- Missing optional pronunciation, context, examples, alternatives, or notes simply removes that row.
- A word response with no valid part of speech or sense is rejected and repaired once.
- Network and provider failures retain Retry and Edit selection actions and never expose raw provider payloads.

## Testing

### Automated

- Decode and round-trip the new multi-part-of-speech word result.
- Decode legacy word cache/history into the compatibility structure.
- Validate pronunciation, part-of-speech, sense, and example limits.
- Ignore an invalid highlighted phrase that is not present in its example.
- Parse equivalent OpenAI JSON-schema and DeepSeek JSON-object responses.
- Perform only one constrained repair attempt for malformed rich word output.
- Keep adversarial selected text in the quoted user-data field.
- Verify deterministic part-of-speech abbreviation and anchor identifiers.
- Verify repeated panel presentation returns the same panel instance rather than constructing a second lookup window.
- Verify the macOS scene list no longer contains a separate lookup `Window`.

### Manual acceptance

- After first Keychain authorization, a shortcut lookup shows exactly one Margin panel.
- Repeated Control–Option–M lookups reuse that panel.
- A word with adjective, noun, and verb entries renders all sections in provider order.
- Each part-of-speech anchor scrolls to the correct heading.
- Escape and returning focus to Books hide the panel.
- Dock reopening presents the same lookup panel.
- Long entries scroll only the body while header, anchors, and actions remain visible.
- Light mode, dark mode, and full-screen Apple Books remain readable.
- Passage translation remains concise and unchanged in information structure.

## Acceptance Criteria

- Exactly one lookup panel is visible at any time.
- The default word panel uses the approved comfortable density and remains within the current screen.
- A multi-part-of-speech word exposes clickable anchor navigation and complete grouped content.
- Definitions follow the approved English-plus-Chinese inline structure with bilingual bullet examples.
- The lookup surface dismisses with Escape or when the user returns to Books.
- Existing history remains readable after upgrade.
- No new book metadata, surrounding text, secrets, or raw provider responses are stored or logged.
