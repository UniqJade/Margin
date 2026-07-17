# Passage Panel and Universal Appearance Design

Date: 2026-07-13  
Status: approved design, pending implementation plan

## Objective

Make sentence and passage translation feel like a compact bilingual reading surface rather than a fixed-size translator window. Short results should occupy only the space they need, while longer results remain easy to read without moving the primary actions off screen. Give Margin a restrained, Claude-inspired orange identity and add explicit System, Light, and Dark appearance choices across macOS, iPhone, iPad, and the iOS Action Extension.

This document supersedes the passage-layout and blue-accent portions of `2026-07-12-dictionary-popover-design.md`. The approved word-dictionary information architecture, multi-part-of-speech anchors, and action behavior remain unchanged.

## Confirmed Decisions

- Sentence and passage results use the approved **B: bilingual comparison page** layout.
- The visual accent uses the approved **B: balanced brand presence** treatment.
- Orange appears in language markers, a thin translation rail, selected states, and limited interaction feedback. Large orange surfaces are not used.
- The copy, speak, save, and retry icons retain their current symbols, order, meaning, and interaction behavior.
- macOS passage panels keep a 540-point width and resize vertically to their content within approximately 280–620 points.
- Original text shows at most four lines by default and offers explicit expand/collapse controls when truncated.
- System, Light, and Dark appearance choices apply to the macOS app, iPhone app, iPad app, and iOS Action Extension.
- System is the default appearance.
- Appearance is local to each device. On iOS/iPadOS, the container app and Action Extension share the same choice; no cloud sync is introduced.
- The richer word-dictionary layout remains fixed at approximately 540 × 620 points on macOS.

## Scope

### In scope

- Replace the current passage card with a stacked bilingual reading layout.
- Add content-driven macOS panel sizing for idle, loading, failure, sentence, and passage states.
- Fold long original selections after four lines, with accessible expansion and collapse.
- Keep actions visible while long content scrolls.
- Add shared semantic color and surface tokens with restrained orange accents.
- Add System, Light, and Dark appearance preferences to Settings on every supported platform.
- Apply the chosen appearance to lookup surfaces, Settings, History, the iOS container app, and the Action Extension.
- Replace existing hard-coded blue Margin accents with the approved orange where they communicate Margin state or identity.
- Preserve platform-native controls, materials, keyboard behavior, VoiceOver labels, and Reduced Motion behavior.

### Out of scope

- User-selectable accent colors beyond the approved orange.
- Per-window or per-feature themes.
- Synchronizing appearance through iCloud or an account.
- Recoloring macOS/iOS system permission dialogs, menus, or other operating-system-owned UI.
- Changing the translation provider contract or passage result model.
- Adding new translation sections merely to fill space.
- Changing the copy, speak, save, or retry icons.
- Changing the approved word dictionary content model or navigation behavior.

## Passage Information Architecture

The passage surface is organized as one continuous bilingual page instead of an elevated gray result card.

### Header

- Retain the Margin wordmark, short product subtitle, and close action.
- Keep provider identity tertiary and unobtrusive; it must not compete with the selected text or translation.
- Avoid a large `PASSAGE` heading because the bilingual section labels already communicate the result type.

### Original section

- Label the section with an orange `EN` marker and a secondary `ORIGINAL` label.
- Render the selected English text in a readable serif style at a quieter contrast than the Chinese translation.
- Limit the collapsed original to four visual lines.
- Show “Expand original” only when the text actually overflows four lines.
- After expansion, replace it with “Collapse original”.
- Preserve text selection and copying in both states.

### Translation section

- Separate it from the original with a thin semantic divider.
- Label it with an orange `中` marker and a secondary `自然译文` label.
- Use a narrow orange editorial rail at the leading edge, not a large colored background.
- Render the natural Chinese translation in a prominent Chinese serif style with comfortable line spacing.
- Keep the translation selectable.

### Optional details

- Show the nuance note only when `nuanceNote` is present and meaningful. It uses a quiet secondary surface or caption treatment and does not appear as a competing card.
- Keep `literalGloss` collapsed behind the existing disclosure behavior.
- Do not synthesize empty placeholders for either optional field.

### Action bar

- Preserve the current copy, speak, save, and retry symbols and their current order.
- Preserve the current save/unsave state behavior and accessibility labels.
- Use orange only for active/selected feedback where needed; inactive icons remain secondary neutral.
- Separate the action row with a hairline divider.
- In long results, pin the action row below the scrolling content so it remains reachable.

## macOS Panel Sizing and Scrolling

The lookup panel retains its 540-point content width. Its target height is calculated from the current content state and clamped to the visible screen.

- Approximate minimum height: 280 points, enough for the header, useful content, and actions without crowding.
- Approximate maximum height: 620 points or the current screen's available visible height when smaller.
- Short sentence results shrink to their measured natural height.
- Loading and failure states use compact, stable target heights and retain the selected text.
- Long passages stop growing at the maximum; only the central reading content scrolls.
- Word results retain the approved fixed dictionary height and internal scrolling.
- A new lookup recalculates the target size from its state and content.
- Resizing preserves the panel's top edge when possible so the result does not appear to jump away from the selected passage.
- Use a short, gentle resize animation. Respect Reduce Motion by applying the size immediately.
- Always clamp the final frame to the active screen's visible bounds.

The sizing interface should be driven by testable layout measurements or a deterministic sizing policy rather than arbitrary delays. Repeated state updates must not create resize loops or continuously shift the panel.

## Universal Appearance System

### Choices

- **Follow System**: no forced color scheme; the UI follows the device appearance and updates when the system changes.
- **Light**: force the Margin-owned SwiftUI surfaces to the light palette.
- **Dark**: force the Margin-owned SwiftUI surfaces to the dark palette.

The labels presented in Chinese UI should communicate “跟随系统 / 白色 / 黑色”; their underlying values remain stable semantic identifiers (`system`, `light`, `dark`).

### Persistence

- Default to Follow System for existing and new users.
- macOS stores the choice in the Mac-local standard preferences introduced by the signing/permissions cleanup.
- iOS/iPadOS stores the choice in the existing shared App Group preferences so the container app and Action Extension agree.
- No old App Group or legacy Mac preference migration is added.
- Appearance changes take effect immediately without restarting Margin.

### Application

- Apply the preferred color scheme at the highest Margin-owned view boundary for each scene or extension surface.
- Settings exposes a dedicated Appearance section using a native picker or segmented control suited to the platform width.
- Apply the same semantic tokens to lookup panels, dictionary results, passage results, Settings, History, empty/loading/failure states, and iOS extension sheets.
- System-owned permission prompts and system menus continue to follow the operating system and may not match a forced Margin theme.

## Color and Typography

The visual language is warm, editorial, and quiet. It is inspired by the restrained warmth associated with Claude, but does not attempt to copy another product pixel-for-pixel.

### Semantic colors

- Accent orange: approximately `#D97745` in light appearance and a slightly brighter approximately `#E78958` in dark appearance.
- Light canvas: warm near-white, approximately `#FAF9F7`.
- Light elevated surface: approximately `#F1F0ED`.
- Light primary text: warm charcoal, approximately `#26231F`.
- Dark canvas: warm near-black, approximately `#171614`.
- Dark elevated surface: approximately `#22201D`.
- Dark primary text: warm off-white, approximately `#F3F0EB`.
- Secondary text and dividers use semantic, contrast-safe neutral values for each scheme.

Exact rendered values may use platform dynamic colors, but their hierarchy and warmth must match the approved prototype. Orange must meet contrast requirements when it conveys state; text meaning must never rely on color alone.

### Typography

- Preserve the compact tracked Margin wordmark.
- Use platform serif typography for original prose and the natural Chinese translation, with appropriate New York/Georgia and Songti/PingFang fallbacks.
- The Chinese translation is larger and higher contrast than the original because it is the lookup result.
- Use system sans-serif typography for labels, controls, notes, and metadata.
- Respect Dynamic Type on iOS/iPadOS and accessibility text-size settings where supported.

## Word Dictionary Compatibility

The word view keeps the previously approved structure:

- fixed headword/pronunciation header;
- clickable multi-part-of-speech anchors such as `adj.`, `n.`, and `v.`;
- scrollable bilingual senses and examples;
- fixed action row.

Only the shared visual tokens change. The former blue active anchor and rail become the approved restrained orange. Content density, navigation, data contract, icons, and window sizing do not change.

## Platform Adaptation

### macOS

- Use the content-driven panel height described above.
- Keep keyboard focus, Escape dismissal, Books deactivation dismissal, text selection, and panel reuse intact.
- Apply appearance to the lookup panel, Settings, and History independently but from the same stored preference.

### iPhone and iPad

- Use the same bilingual hierarchy, orange accent, four-line original fold, and optional details.
- Let the platform sheet or containing scene determine available height rather than reproducing the AppKit frame algorithm.
- Keep the action bar readily reachable and use scrolling for long content.
- The Action Extension reads the shared appearance preference before rendering and reacts to later changes when reopened.

## Accessibility and Interaction

- All existing action icons retain textual accessibility labels and adequate hit targets.
- Expand/collapse exposes its state to VoiceOver.
- Language markers have meaningful combined labels and do not require the user to understand color.
- Ensure primary/secondary text and orange state indicators have sufficient contrast in both schemes.
- Respect Reduce Motion for panel resizing and disclosure animations.
- Preserve keyboard navigation and visible focus rings on macOS.
- Do not move focus merely because the panel recalculates its height.

## Testing

### Automated

- Verify the appearance enum maps System to no forced scheme, Light to light, and Dark to dark.
- Verify Follow System is the default when no preference exists.
- Verify Mac persistence remains local and does not access the iOS App Group.
- Verify iOS container and Action Extension read the same shared preference.
- Verify passage results render the bilingual section structure without the former large card.
- Verify four-line folding, expansion, and collapse preserve the full original text.
- Verify optional nuance and literal-gloss sections appear only when present.
- Verify copy, speak, save, and retry actions retain their symbols, order, and handlers.
- Verify deterministic panel target heights for compact, maximum, and fixed word-result policies.
- Verify height clamping respects visible screen bounds and top-edge preservation.
- Verify Reduce Motion disables animated resizing.
- Verify XcodeGen regeneration preserves the settings, storage, and target wiring.

### Manual acceptance

- Test Follow System, Light, and Dark on macOS, iPhone, iPad, and the Action Extension.
- Change appearance while Margin is running and confirm its owned surfaces update without restart.
- Look up a short sentence and confirm the Mac panel contains no large unused lower area.
- Look up a long passage and confirm content scrolls while the action row remains visible.
- Expand and collapse a long original selection.
- Confirm copy, speak, save, and retry icons look and behave exactly as before.
- Confirm orange is visible as a restrained identity but never becomes a large reading background.
- Confirm word part-of-speech anchors and dictionary scrolling remain unchanged except for the shared accent color.
- Confirm system permission dialogs remain system-styled and do not cause duplicate Margin windows.

## Acceptance Criteria

- Passage results use the approved bilingual comparison hierarchy.
- A short macOS sentence result produces a compact panel with no uncomfortable empty lower region.
- A long result remains within the current screen and keeps actions reachable.
- The original selection is limited to four lines by default and can be fully expanded and collapsed.
- System, Light, and Dark choices work across all Margin-owned macOS, iPhone, iPad, and Action Extension surfaces.
- The approved balanced orange treatment is consistent in both light and dark appearance.
- Copy, speak, save, and retry icons and behaviors are unchanged.
- Word dictionary layout, multi-part-of-speech navigation, and fixed size remain functionally unchanged.
- No new selected text, metadata, secrets, provider responses, or appearance data are sent to cloud synchronization.
