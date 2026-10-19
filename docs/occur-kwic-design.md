# occur-kwic design

This document records the initial implementation and its design decisions as of 2026-10-20. See the [user guide](../README.md) and [validation record](implementation-checks.md). The original [eyegrep.el](../eyegrep.el) is preserved unchanged with characterization tests.

## Purpose and interface

The package aligns search results by their matches to make surrounding context easier to compare with less horizontal eye movement. It uses KWIC (Key Word In Context) presentation with familiar Occur navigation. The plain description matters alongside the term “KWIC”: someone looking for grep-like output with matches lined up vertically should be able to recognize the tool without knowing that term.

The Emacs package is an independent project named `occur-kwic`. A future CLI is outside this repository's scope.

Core requirements:

- One result row per non-overlapping match, including multiple matches on a source line.
- Configurable left, center, and right match alignment, with left as the default.
- Full accessible source lines retained in result text; cropping and padding belong to the display layer.
- Layout follows each result window's width, including when a buffer appears in several windows.
- Occur-like navigation and refresh, with result editing explicitly disabled in the initial version.
- Source narrowing respected; long matches cropped without wrapping; actual multiline matches rejected.

## Alignment model

`occur-kwic-alignment` selects the part of a match that sits at the midpoint of the result window's entire text area. The line-number prefix occupies part of that area; it is not subtracted before finding the midpoint.

| Value | Anchor |
| --- | --- |
| `left` (default) | Match start |
| `center` | Match center |
| `right` | Match end |

Left alignment places match starts together at the window midpoint. Right alignment places match ends there. Available context is computed separately on each side from that anchor and the match width. Short context receives display-only padding rather than shifting the anchor.

Layout is measured in display columns, rather than character counts. An odd-width match in center alignment rounds its start to the right. Ordinary full-width characters and combining marks are covered by tests. Tabs use the source's `tab-width`, expanded from the start of the accessible source line. Pixel-perfect behavior with proportional fonts and complex emoji sequences is outside the current guarantee.

A match wider than the available area stays anchored and is clipped without wrapping. At extremely narrow widths, the prefix and anchor may no longer fit together, and a visible match cannot be guaranteed. Widening restores the ordinary view without changing the stored text.

The [legacy layout audit](layout-audit.md) distinguishes stable ordinary-character placement from tab and search-loop problems. Legacy rounding and fixed offsets are useful comparison data, rather than requirements to reproduce every old coordinate.

## Relationship to Occur

`occur-kwic-mode` derives from `occur-mode`. There is no global advice changing ordinary Occur. Result rows carry the `occur-target` and `occur-match` information used by standard navigation, with source markers separate from display offsets.

The package reuses familiar regexp input and history, case handling, source navigation, match movement, `next-error`, refresh, quitting, Occur faces, and normal result-window placement. It uses its own result generation because ordinary line-based Occur output does not provide one row per match.

Initialization runs `occur-mode-hook` and `occur-kwic-mode-hook`. Successful searches run `occur-kwic-hook`. The ordinary `occur-hook` is not run: some of its functions assume line-based output or an exact `occur-mode` major-mode name.

The initial scope includes the active region. It excludes context-line prefix arguments, collection prefix arguments, and multiple-buffer search. These differences are explicit in the user guide.

## Stored data and display views

Each match entry stores its source line number, full accessible line text, cumulative display columns, match offsets within the line, and source markers. Several matches on one source line duplicate that line's text in separate result rows.

“Full line” means the portion inside the source buffer's accessible search bounds. Collection does not widen the source to retrieve context outside narrowing or a selected region.

Result text is shared across all windows. Each view uses overlays with a `window` property for hidden context and display-only padding. The underlying source text is not cropped or padded. Tabs remain tabs in the stored text, with their source-column widths represented through display properties.

Lifecycle rules:

- Initial display uses the actual result window's dimensions.
- Window size and buffer-change hooks update layout from stored entries without repeating the search.
- Resizing leaves text, match count, order, and source targets unchanged.
- `g` searches the source again and replaces the snapshot.
- Views no longer showing the result release their overlays. Killing or replacing results releases private markers and overlays.
- Cloning creates an independent snapshot with separate mutable markers and display state.

Both automated tests and GUI checks cover differently sized windows and resizing. Large-result performance and older-version behavior still need broader verification.

## Why result editing is disabled

Ordinary Occur Edit applies changes to source lines. Keeping full lines and display-only padding helps preserve that model, but one source line can appear in several KWIC rows. Editing one copy would leave the other copies stale. Source jump targets and editable line bounds also serve different purposes.

Sharing markers or references alone does not synchronize copied strings. A future shared-line model would still have to handle edits that add or remove matches and split or join source lines. That requires re-searching and rebuilding results as well as synchronizing text.

The initial version therefore keeps results read-only, disables the edit key and menu, and rejects interactive entry into `occur-edit-mode`, including via `M-x`. Ordinary Occur remains unaffected. The supported workflow is to edit the source and press `g` to refresh. No automatic source-to-result synchronization is attempted.

## Search bounds and exceptional matches

### Narrowing and regions

Search and context collection stay inside the source's accessible bounds, further restricted by an active region. Region endpoints are retained as markers. Refresh combines those tracked endpoints with the source's current narrowing.

Visual cropping is separate from narrowing. Copying selected result text includes hidden context and original tabs, but no display padding. Narrowing the result buffer restricts copying and searching in the normal Emacs way.

Reference experiments with standard Occur in the local Emacs 31.1 build showed:

- Narrowing `prefix inner-X suffix` to `inner-X` and searching for `X` also restricted result context to `inner-X`.
- Widening the source and reverting the Occur result included newly accessible matches.
- Enabling `truncate-lines` did not remove underlying text from the copyable result.
- Narrowing the result itself to `inner-X` restricted the copied text to that portion.

### Multiline and zero-width matches

Search operates over the accessible buffer range, rather than applying the regexp separately to each line and changing its meaning. If an actual match contains a newline, collection raises an explanatory error. The regexp's spelling alone is not used to reject it. Collection completes before replacing results, so regexp errors and unsupported multiline matches leave the old snapshot intact.

Zero-width matches explicitly advance the search. Their position is shown with a display-only `|`; the marker is not inserted into the underlying text. A final newline does not introduce an extra empty result row.

### Incremental search and full-line display

`v` toggles a row's full text. During incremental search, all rows are revealed; afterward the final result row remains expanded. Full-line expansion applies to every window showing that result buffer because Emacs's buffer-level invisibility checks also inspect invisible overlays for other windows. Revealing only the selected window was insufficient and failed a GUI search check. Ordinary cropped KWIC views remain independent by window width.

## Sources consulted

The local Emacs 31.1 development build's `replace.el` was inspected for Occur modes, result generation, navigation, refresh, and editing. The implementation adapts marker representation for older Occur versions, but actual runtime verification on those versions remains pending.

- [GNU Emacs Manual: Other Search-and-Loop Commands](https://www.gnu.org/software/emacs/manual/html_node/emacs/Other-Repeating-Search.html)
- [GNU Emacs Lisp Reference Manual: Overlay Properties](https://www.gnu.org/software/emacs/manual/html_node/elisp/Overlay-Properties.html)
- [GNU Emacs Lisp Reference Manual: Window Hooks](https://www.gnu.org/software/emacs/manual/html_node/elisp/Window-Hooks.html)
- [GNU Emacs Manual: Narrowing](https://www.gnu.org/software/emacs/manual/html_node/emacs/Narrowing.html)
- [GNU Emacs Lisp Reference Manual: Invisible Text](https://www.gnu.org/software/emacs/manual/html_node/elisp/Invisible-Text.html)
