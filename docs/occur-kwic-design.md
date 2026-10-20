# occur-kwic design

This document describes occur-kwic 0.1.1 and its design decisions as of 2026-10-20. See the [user guide](../README.md) and [validation record](implementation-checks.md). The original [eyegrep.el](../legacy/eyegrep.el) is preserved unchanged with characterization tests.

## Purpose and interface

The package aligns search results by their matches to make surrounding context easier to compare with less horizontal eye movement. It uses KWIC (Key Word In Context) presentation with familiar Occur navigation. The plain description matters alongside the term “KWIC”: someone looking for grep-like output with matches lined up vertically should be able to recognize the tool without knowing that term.

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

The column model assumes Emacs's logical widths agree with actual glyph advances. Font selection, Unicode East Asian Width, and Emacs's language and character-width settings can disagree, including for ambiguous-width characters. Misalignment can therefore occur even with monospaced fonts and accumulate across the displayed context. This is a display limitation; source text and stored result text remain intact. Automatic width validation, font adjustment, and character-width correction are outside the package's scope.

The layout also assumes logical character order corresponds to horizontal
position. Bidirectional reordering breaks this assumption independently of
glyph widths: a match inside a right-to-left run may be positioned according
to context logically after it. Hebrew and Arabic GUI checks have reproduced
different match positions across rows, despite equal-width glyphs. Forcing
`bidi-paragraph-direction` to `left-to-right` leaves reordering within those
runs intact and is insufficient. Reliable bidirectional alignment and cropping
remain unresolved; disabling natural reading order is not a fix. Basic search,
text retention and source navigation are covered separately by a passing test.

A match wider than the available area stays anchored and is clipped without wrapping. At extremely narrow widths, the prefix and anchor may no longer fit together, and a visible match cannot be guaranteed. Widening restores the ordinary view without changing the stored text.

The [legacy layout audit](layout-audit.md) distinguishes stable ordinary-character placement from tab and search-loop problems. Legacy rounding and fixed offsets are useful comparison data, rather than requirements to reproduce every old coordinate.

## Relationship to Occur

`occur-kwic-mode` derives from `occur-mode`. There is no global advice changing ordinary Occur. Result rows carry the `occur-target` and `occur-match` information used by standard navigation, with source markers separate from display offsets.

The package reuses familiar regexp input and history, case handling, source navigation, match movement, `next-error`, refresh, quitting, Occur faces, and normal result-window placement. It uses its own result generation because ordinary line-based Occur output does not provide one row per match.

Initialization runs `occur-mode-hook` and `occur-kwic-mode-hook`. Successful searches run `occur-kwic-hook`. The ordinary `occur-hook` is not run: some of its functions assume line-based output or an exact `occur-mode` major-mode name.

The initial scope includes the active region. It excludes context-line prefix arguments, collection prefix arguments, and multiple-buffer search. These differences are explicit in the user guide.

## Stored data and display views

Each match entry stores its source line number, match offsets within the line,
source markers, and references to the full accessible line text and cumulative
display columns. Matches on the same source line share that immutable text and
column vector. The result buffer still contains a full copy of the line in each
match's separate result row.

Collection visits matches in source order and keeps a single current-line
cache, reusing line boundaries, the line number, text, and column measurements
until the next source line. Each search builds fresh line data, so refresh
does not reuse stale source text. Match offsets, targets, and result-row
positions remain separate for every entry.

Column measurements use `char-width` for each character, with tabs expanded
separately at the source's tab stops. This avoids allocating a one-character
substring for every width lookup. It also avoids asking automatic composition
to measure a combining mark in isolation: on GUI Emacs, that could count an
accent as a spacing character even when it follows a base character in the
source. Widths still follow the buffer's display table and `char-width-table`.
This remains a character-column model, without measurement of whole shaped
clusters or font-specific pixel advances. Sharing avoids repeated line-width
calculation and column-vector allocation.
The full result text can still grow quadratically when a long line has many
matches, because that line is inserted once per match.

Collection estimates result-row bytes before constructing output. The
`occur-kwic-output-size-warning-threshold` option defaults to 10 MiB; nil
disables it. Above the threshold, an interactive confirmation explains the
possible slowdown or memory exhaustion. Refusal or quit follows collection's
cleanup path and preserves previous results. Acceptance disables further size
confirmations for that search; refresh starts a fresh estimate. Batch searches
signal a user error instead of prompting.

The running estimate sums each repeated line's multibyte byte count and the
line-number prefixes and newlines for all entries so far. A larger source line
number widens every prefix, so its overhead is applied to all collected rows.
Each source line's byte count is cached alongside its text; unibyte lines are
measured after conversion to the result's multibyte representation. The check
precedes allocation of the crossing entry's markers and, for a newly encountered
line, its column vector. After acceptance or with warnings disabled, byte
counting is skipped. The header and metadata are excluded. This is an early
warning based on accumulated output, not a match-count cap, total-memory limit,
or prediction of the final size.

“Full line” means the portion inside the source buffer's accessible search bounds. Collection does not widen the source to retrieve context outside narrowing or a selected region.

Result text is shared across all windows. Each view uses overlays with a `window` property for hidden context and display-only padding. The underlying source text is not cropped or padded. Tabs remain tabs in the stored text, with their source-column widths represented through display properties.

Lifecycle rules:

- Initial display uses the actual result window's dimensions.
- Window size and buffer-change hooks update layout from stored entries without repeating the search.
- Resizing leaves text, match count, order, and source targets unchanged.
- `g` searches the source again and replaces the snapshot.
- Views no longer showing the result release their overlays. Killing or replacing results releases private markers and overlays.
- Cloning creates an independent snapshot with separate mutable markers and display state.

Source markers are detached in reverse creation order, including each pair's
end marker before its start marker. Collection's partial list is already in
that order; completed result lists are traversed in reverse without changing
their cons cells. This avoids repeatedly scanning past the result's own newer
markers in Emacs's marker chain. Unrelated live markers in the source can
still add scanning cost, so cleanup is not guaranteed to be linear in every
buffer configuration.

Generation retains a cleanup path for all collected entries until population
and the first layout complete. Failure during collection preserves previous
results. Failure after output construction begins discards the incomplete
result buffer, including a buffer being refreshed; it does not restore the
previous snapshot. Cleanup also releases region and private navigation-arrow
markers and clears expanded-row references. It leaves shared navigation arrows
belonging to other buffers alone. Clone entries acquire ownership incrementally,
so interrupted cloning can discard its partial copies without touching the
original's markers or overlays.

Overlay allocation is registered with its view before properties are assigned.
A view's cache is invalidated before deleting old overlays and updated only
after drawing completes. An interrupted redraw can therefore be retried without
orphaning overlays or accepting an incomplete layout as current.

Both `c` and `M-x clone-buffer` use standard `clone-buffer`, with a buffer-local
`clone-buffer-hook` that detaches KWIC state. The hook copies entries and source
markers, copies region markers, rebinds result text properties to the copied
entries, and drops borrowed view caches without deleting the original overlays.
Each snapshot has its own navigation arrow. Immutable source text and column
vectors can remain shared. Standard cloning preserves point, mark, narrowing,
and naming behavior; expansion is mapped to the corresponding copied entry.
The `no-clone-indirect` mode property rejects ordinary indirect cloning commands,
whose shared text is incompatible with independently refreshed snapshots.

Both automated tests and GUI checks cover differently sized windows and resizing. Large-result performance and older-version behavior still need broader verification.

## Why result editing is disabled

Ordinary Occur Edit applies changes to source lines. Keeping full lines and display-only padding helps preserve that model, but one source line can appear in several KWIC rows. Editing one copy would leave the other copies stale. Source jump targets and editable line bounds also serve different purposes.

Sharing markers or references alone does not synchronize copied strings. A future shared-line model would still have to handle edits that add or remove matches and split or join source lines. That requires re-searching and rebuilding results as well as synchronizing text.

The initial version therefore keeps results read-only, disables the edit key and menu, and rejects interactive entry into `occur-edit-mode`, including via `M-x`. Ordinary Occur remains unaffected. The supported workflow is to edit the source and press `g` to refresh. No automatic source-to-result synchronization is attempted.

## Search bounds and exceptional matches

### Narrowing and regions

Search and context collection stay inside the source's accessible bounds, further restricted by an active region. Region endpoints are retained as markers. Refresh combines those tracked endpoints with the source's current narrowing. An empty or disjoint intersection produces no matches; reversed intersection endpoints must not be passed to `narrow-to-region`, which would search the gap between the two ranges.

Line numbers are relative to the source's accessible beginning before applying the region, matching ordinary Occur. Collection records a line offset before its temporary narrowing so selecting a region does not restart numbering. Source narrowing still defines the numbering origin.

Collection binds `inhibit-field-text-motion` so line boundaries follow actual newlines and search bounds rather than `field` properties. Prompt/input fields in shell or REPL buffers therefore neither crop context nor cause a match spanning a field boundary to be rejected as multiline. This does not widen the search bounds or modify the source's field properties.

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

Choosing an alignment returns every row to KWIC display and resets horizontal scrolling in all result windows, including when the same alignment is selected again. Cropped display disables automatic horizontal scrolling: the uncropped header can otherwise make redisplay scroll the entire window after layout has already reset its scroll position. Expanded views use the global `auto-hscroll-mode` setting so incremental search and cursor movement can expose full-line context. Scroll reset on alignment selection is independent of the layout cache.

## Sources consulted

The local Emacs 31.1 development build's `replace.el` was inspected for Occur modes, result generation, navigation, refresh, and editing. The implementation adapts marker representation for older Occur versions, but actual runtime verification on those versions remains pending.

- [GNU Emacs Manual: Other Search-and-Loop Commands](https://www.gnu.org/software/emacs/manual/html_node/emacs/Other-Repeating-Search.html)
- [GNU Emacs Lisp Reference Manual: Overlay Properties](https://www.gnu.org/software/emacs/manual/html_node/elisp/Overlay-Properties.html)
- [GNU Emacs Lisp Reference Manual: Window Hooks](https://www.gnu.org/software/emacs/manual/html_node/elisp/Window-Hooks.html)
- [GNU Emacs Manual: Narrowing](https://www.gnu.org/software/emacs/manual/html_node/emacs/Narrowing.html)
- [GNU Emacs Lisp Reference Manual: Invisible Text](https://www.gnu.org/software/emacs/manual/html_node/elisp/Invisible-Text.html)
