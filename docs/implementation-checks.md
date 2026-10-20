# Implementation validation

Recorded on 2026-10-20 for [occur-kwic.el](../occur-kwic.el), covering the initial 0.1.0 implementation and follow-up fixes and optimizations for 0.1.1. The sections retain the test counts and results at each stage. The legacy implementation remains unchanged.

## Automated checks

`make check` checked parentheses, loading, and byte compilation with warnings treated as errors for both implementations, then ran 39 ERT tests. All 22 new-implementation tests passed. Of the 17 legacy tests, two were expected failures documenting tab alignment and zero-width search progress. There were no unexpected results.

The new tests observe result text, window-specific display properties, source markers, and ordinary Occur navigation. They do not simply duplicate the layout formula as their expected-value calculation.

## Portable test entry points

`scripts/test.sh` and `scripts/test.ps1` invoke the shared `scripts/run-tests.el` runner. The default runs source checks and ERT; `--test-only` (POSIX) or `-TestOnly` (PowerShell) runs ERT alone. The Make targets use the POSIX entry point.

Both entry points completed all 39 tests as expected on macOS. Additional checks covered macOS's `/bin/sh` and Bash 3.2, invocation outside the repository, repository and Emacs executable paths containing spaces, an explicit PowerShell `-Emacs` parameter overriding the environment, and propagation of a simulated Emacs failure with exit code 23. Unknown runner arguments returned a nonzero exit code. The original `eyegrep.el` SHA-256 remains `4b7beda35bee6557fc0e19850d5c0bd4bd4e5460c915c20115ffa2b9626b34c5`.

The initial PowerShell checks used `pwsh` on macOS. Subsequent Windows execution and display checks are recorded below.

## GUI alignment and resizing

GUI checks used a dedicated frame and disposable buffers in a local development build of Emacs 31.1 on macOS / arm64. Existing key bindings and user settings were left unchanged. Lines containing tabs, Japanese text, and long context were displayed in two windows of different widths. Actual coordinates from `posn-at-point` and screenshots were inspected.

The frame's canonical character width was 13 pixels. With text-area widths of 39 and 65 columns, left-aligned matches `X`, `YY`, and `ZZZ` all started at 247 and 416 pixels respectively, relative to their windows. Right alignment made their ends coincide. Center alignment showed the expected half-column odd/even rounding difference.

After resizing to 44 and 60 columns, all match starts moved to 286 and 390 pixels respectively. The layout function was not called manually after resizing; redisplay hooks updated the views.

## Searching hidden context

An initial implementation revealed text only in the selected window. Invisible overlays left in the other window affected Emacs's buffer-level search checks: searching for a visibly displayed `HIDDEN_START` failed.

The implementation now reveals all rows in every view during incremental search and leaves the final result row expanded afterward. Tests check buffer-level `invisible-p` as well as window-specific display properties. After the fix, ordinary GUI incremental search found and highlighted `HIDDEN_START`. The `v` command restores KWIC display.

## Initial trial and extremely narrow windows

During my initial trial, I found no problems. Near the minimum window width, some rows retained part of the match while others retained only context. I did not regard that difference as meaningful when all rows were already incomplete.

When the midpoint overlaps the line-number area, the same cropping rules can leave different fragments depending on match position, match width, and context length. No special rule was added to force a uniform appearance or prioritize matches at those widths. This is documented as a display limitation.

A regression test exercises three-digit line numbers with all three alignments at widths 3, 4, 5, 6, 8, 10, and 12. It verifies that layout does not error, full text and source markers survive, and widening restores ordinary centered anchors in left alignment. Exact tiny-width fragments are not fixed as part of the interface. This test did not change the implementation's behavior.

## Alignment switching follow-up on Windows

On macOS, I observed intermittent alignment drift and alignment selections that
appeared ineffective. Investigation on Windows reproduced three
conditions; these do not establish that every macOS symptom I observed has the
same cause:

- With point at the end of a long result header, automatic horizontal scrolling
  during redisplay shifted all aligned rows after layout had reset the scroll.
  A GUI regression test observed a 147-column scroll in a narrow result window.
- Full-line display persisted across alignment selections. The expanded row
  bypassed alignment, and its automatic horizontal scrolling could move the
  other, cropped rows out of view.
- Reselecting the current alignment left an existing horizontal scroll intact
  because the cached layout did not need rebuilding.

Alignment selection now ends full-line display and resets horizontal scrolling
in all result windows, regardless of whether layout needs rebuilding. Cropped
KWIC display disables automatic horizontal scrolling. Expanded views retain
the global scrolling preference so full-line navigation and search remain usable.
The distinction between setting a scroll position and subsequent automatic
scrolling is documented in the
[Emacs Lisp manual](https://www.gnu.org/software/emacs/manual/html_node/elisp/Horizontal-Scrolling.html).

Validation used GNU Emacs 31.1, build 1 of 2026-09-17,
`x86_64-w64-mingw32`, on Windows. Source checks and warning-free byte compilation
passed. At that point the batch suite had 41 tests, all with expected results, including
the two legacy expected failures. Both new batch regressions failed before the
fix and passed afterward.

Two separate GUI regressions also failed before the fix and passed afterward.
They use the actual `a` binding and completing minibuffer, force redisplay, and
check match coordinates with `posn-at-point`. Coverage includes a long header,
full-line expansion and automatic scrolling, repeated alignment selection,
two windows of different widths, and resizing through the real redisplay hooks.
The default fixed-width GUI font was used. Run these checks in a fresh process
with `emacs -Q -l scripts/run-gui-tests.el`; the runner saves a log and exits.

The alignment fix has not yet been rerun on macOS. The initial macOS GUI checks
above predate this fix.

## Search bounds, line numbers, and source fields

Follow-up validation on the same Windows Emacs 31.1 build covered three
collection fixes. Each new regression failed before the fix and passed afterward:

- Refreshing after narrowing the source away from the saved region finds no
  matches. Tests cover disjoint bounds in either order and touching bounds,
  with a match in the intervening gap to catch accidental searches outside
  both ranges. The source restriction is preserved.
- Region searches retain the source's line numbers, including regions beginning
  inside a line. An existing source narrowing still determines the numbering
  origin, as in ordinary Occur. Context stays inside the search bounds.
- Field boundaries neither truncate line context nor count as newlines. Tests
  cover matches within either field and across the boundary, preservation of
  source field properties, and a region that excludes prompt text. The existing
  regression still rejects matches containing actual newlines.

Source checks and warning-free byte compilation passed. All 44 batch tests
completed with expected results: 27 new-implementation passes, 15 legacy passes,
and two legacy expected failures. These are batch checks of collection behavior;
the GUI alignment results above were recorded before this collection follow-up.

## Standard buffer cloning

Cloning now uses the standard command and a buffer-local `clone-buffer-hook`,
so `c` and `M-x clone-buffer` detach the same private state. Text properties
are rebound to the copied entries and source markers; region markers and
navigation arrows are independent. The hook drops borrowed display caches
without deleting the original overlays. Indirect cloning commands are rejected
through the mode's `no-clone-indirect` property.

Three new batch regressions failed before this change and passed afterward.
They exercise `c`, `M-x clone-buffer`, and named non-displayed clones; closing
either snapshot first; refresh and source navigation from the survivor; and
preservation of point, mark, narrowing, alignment, expansion, and navigation
arrows. Entries outside a cloned restriction are rebound too. Indirect cloning
is rejected for KWIC results while ordinary source buffers remain cloneable.

Source checks and warning-free byte compilation passed on the same Windows
Emacs 31.1 build. All 47 batch tests completed as expected, including the two
legacy expected failures. All three GUI tests passed. The added GUI test uses
`C-u c` and the real naming minibuffer, then checks actual alignment coordinates
in the clone and original after redisplay and after closing the clone.

## Sharing source-line data

Matches from the same source line now share immutable line text and cumulative
column measurements. A single current-line cache also avoids repeating line
boundary and line-number lookup for those matches. Searches and refreshes build
fresh caches. Per-match offsets, markers, and result-row positions remain
independent. This optimization initially left the per-character `string-width`
calculation unchanged; the subsequent width change is described below.

A new regression failed before the change: 201 matches across three source
lines caused 201 column-table calculations instead of three. It now checks
sharing within each physical line, independent source targets, unchanged
snapshot text after source edits, and fresh data after refresh. Another test
covers two matches sharing a line with Japanese text, a tab, and a combining
character under all three alignments. All 49 batch tests completed as expected,
including the two legacy expected failures. Source checks, warning-free byte
compilation, and all three GUI regressions passed on the same Windows build.

Phase measurements used synthetic ASCII input on Windows Emacs 31.1. Times
below are milliseconds, taking the median of three trials with byte-compiled
functions. They cover match collection, result-buffer population, and overlay
layout; actual GUI redisplay is excluded. Column calculation was timed through
a temporary wrapper. Trials ran garbage collection before measurement and
included any collection that occurred within the timed phases. These are
small local comparisons, not a general performance guarantee.

| Input | Before sharing | After sharing |
| --- | ---: | ---: |
| 1,000 distinct lines of about 80 characters, one match each | 29.4 | 30.9 |
| One 10,000-character line with 10 matches | 20.3 | 2.2 |
| One 1,600-character line with 800 matches | 187.2 | 29.8 |

In the dense-line case, column calculation dropped from 800 calls to one, and
retained column-vector elements dropped from 1,280,800 to 1,601. The result
buffer still contained 1,282,439 characters in both versions. Sharing therefore
reduces repeated computation and auxiliary storage without removing the cost
of retaining each match's full line in the result buffer. No improvement is
expected from sharing when each source line has only one match.

## Character-width calculation

The column-table loop now calls `char-width` on the integer returned by `aref`,
avoiding a one-character substring allocation and a string-width lookup on each
iteration. Tabs still advance to the next source tab stop.

Source review covered `Fchar_width`, `Fstring_width`, and `lisp_string_width` in
[Emacs 27.1 character.c](https://github.com/emacs-mirror/emacs/blob/emacs-27.1/src/character.c)
and the [current development implementation](https://github.com/emacs-mirror/emacs/blob/master/src/character.c).
Both width functions use the same internal `char_width` helper for ordinary
characters, including display-table replacements. Source-line snapshots have
no text properties, so explicit composition properties are not retained.
Newer `string-width` implementations also check automatic composition. That
path can run even on a one-character string when the current source buffer is
displayed. In `compose-gstring-for-graphic` in
[composite.el](https://github.com/emacs-mirror/emacs/blob/master/lisp/composite.el),
a combining mark without a base character can be given spacing width.

On Windows Emacs 31.1, batch comparisons over U+0000 through U+10FFFF found
no differences between `char-width` and single-character `string-width`.
All 256 unibyte values also agreed with both buffer representations and both
`ctl-arrow` settings. GUI spot checks did find differences: U+0301, U+0338,
and U+05B0 measured one column as isolated strings but zero with `char-width`.
This means the two approaches are not universally interchangeable.

An actual GUI regression reproduced the resulting defect with `e` followed by
U+0301 before an ASCII match. The old implementation placed the match one
column (8 pixels in that frame) left of its intended anchor. The new one passes
all three alignments and retains the same column measurements and correct
position after hiding or showing the source and refreshing. A batch regression
also checks tabs, combining marks, variation selectors, joiners, unibyte
characters, controls, display-table replacements, and a modified
`char-width-table`. All 50 batch tests completed as expected, including the
two legacy expected failures; source checks, warning-free byte compilation,
and all four GUI tests passed. macOS runtime verification remains pending.

Performance comparisons used the shared-line implementation on the same
Windows build, alternating the two width functions over nine trials. Medians
include garbage collection during measurement. With byte-compiled functions,
column calculation for 320,000 ASCII characters dropped from 69.5 to 15.2 ms;
mixed Japanese, tabs, and combining marks dropped from 70.3 to 18.1 ms.
Collection, result-buffer population, and overlay layout together dropped
from 28.6 to 20.1 ms for 1,000 80-character lines with one match each. The
same workload with interpreted functions dropped from 97.0 to 90.1 ms.
Actual GUI redisplay is excluded. For 800 matches on one 1,600-character
line, sharing already leaves only one width calculation, and total times
were close: 27.7 versus 26.8 ms with byte-compiled functions.

The character-column model does not measure complete shaped clusters.
Font-dependent advances, isolated combining marks, and complex scripts or
emoji remain outside the pixel-positioning guarantee; this change does not
provide general composition support.

## Resource cleanup and interrupted generation

Emacs's `unchain_marker` scans a buffer's marker chain to detach a marker;
`attach_marker` adds new markers at its front. See
[marker.c](https://github.com/emacs-mirror/emacs/blob/master/src/marker.c).
Detaching a completed result's markers oldest first therefore repeatedly
scanned past its own newer markers. Cleanup now reverses entry traversal and
detaches each end marker before its start marker. Partial collection and clone
lists already have newest entries first and are released in that order.
Entry and target lists themselves are left intact.

An injected quit during population previously left incomplete entries in a
live result buffer; its next window refresh failed on missing row positions.
Generation now discards that buffer on error or quit and releases all collected
markers, including entries whose rows were never inserted. Cancellation while
still collecting matches preserves existing results. A refresh that has begun
rebuilding output discards its incomplete result rather than restoring the old
snapshot. Failed clones release their partial copies and leave the original
intact. Small marker-pair allocation and registration steps defer pending quits
until ownership is recorded; cleanup finishes with quitting inhibited.

Overlay ownership is recorded before property assignment, and layout cache
state is committed only after a redraw completes. Cleanup also clears expanded
entries, region markers, and owned navigation arrows without changing shared
arrows used by other buffers.

Seven added batch tests cover collection and population failure, a pending quit
during marker allocation, failed cloning, interrupted overlay assignment and
redraw recovery, idempotent cleanup with unrelated markers, and shared-arrow
isolation. Error and quit paths are both exercised where applicable. The batch
suite completed all 57 tests as expected, including the two legacy expected
failures. Source checks, warning-free byte compilation, and all four GUI tests
also passed on the same Windows Emacs 31.1 build.

The bounded synthetic comparison in
[scripts/benchmark-cleanup.el](../scripts/benchmark-cleanup.el) can be run from
the repository with `emacs -Q --batch -l scripts/benchmark-cleanup.el`. It compares
the previous release order with the new one on Windows Emacs 31.1, using
interpreted functions and the median of three trials. Setup and explicit
pre-trial garbage collection are excluded; any GC during the timed operation
is included. Buffer-kill measurements include overlays and text properties,
but no GUI redisplay.

| Operation | Previous order (ms) | New order (ms) |
| --- | ---: | ---: |
| Release 2,500 matches' markers | 41.0 | 1.3 |
| Release 5,000 matches' markers | 156.6 | 2.6 |
| Release 10,000 matches' markers | 676.1 | 5.4 |
| Release 20,000 matches' markers | 2,976.5 | 11.4 |
| Kill a 5,000-result buffer with overlays | 184.3 | 3.5 |
| Release 5,000 matches with 10,000 newer unrelated source markers | 593.8 | 221.2 |

The last case demonstrates a remaining cost: newer markers owned by another
result or clone still have to be scanned on each detach. No universal linear
cleanup bound is claimed. Cleanup alone does not limit result text size;
full source-line repetition can still exhaust memory for broad patterns.

## Output-size confirmation

Collection now checks estimated result-row bytes against
`occur-kwic-output-size-warning-threshold`, initially 10 MiB. It counts the
whole line once per match, plus all line-number prefixes and newlines, using
Emacs's internal multibyte byte count. It accounts for prefix growth when
later matches need more line-number digits and for non-ASCII bytes in unibyte
sources. Each source line's byte count is cached. A crossing is checked before
allocating the new entry's markers or a new line's column vector.

Interactive searches ask once whether to continue, explaining possible
slowdown or memory exhaustion and the need for additional metadata. Refusal
or quit releases partial collection and preserves previous results. Acceptance
allows the entire remaining search without further size confirmations; each
refresh starts over. Nil disables the check. Batch searches signal a user error
without prompting. The estimate excludes the header and metadata and does not
predict the final result size or guarantee a safe memory bound.

Five added batch tests compare the estimate with actual generated row bytes
for multibyte text, unibyte text and widening line-number prefixes; check
threshold equality and disabled warnings; verify one confirmation per search
and a fresh confirmation on refresh; and exercise refusal, quit and batch
errors while checking that previous results survive and new markers are
released. The batch suite completed all 62 tests as expected, including the
two legacy expected failures, with warning-free source compilation on Windows
Emacs 31.1.

## Bidirectional text audit

The preceding suites did not test Hebrew or Arabic display. A follow-up GUI
audit on the same Windows Emacs 31.1 build used synthetic Hebrew and Arabic
text, all three alignments, and both default paragraph-direction detection and
an explicit `left-to-right` direction. The default Courier New rendered the
tested letters with an eight-pixel advance, matching the frame's column width;
the font had glyphs for the tested characters.

The following two-line buffers reproduce an alignment failure. Search for
`שלום` in the Hebrew buffer or `مرحبا` in the Arabic buffer:

```text
אבג שלום דהו
אבגדהוז שלום אב
```

```text
عالم مرحبا سلام
سلام عالم مرحبا في
```

In an 80-column window with an eight-pixel character width, left alignment
should put each match's visual left edge at x=320. The measured match extents
were:

| Sample | First row's left edge (px) | Second row's left edge (px) | Difference |
| --- | ---: | ---: | ---: |
| Hebrew | 320 | 280 | 5 columns |
| Arabic | 312 | 264 | 6 columns |

Center and right alignment also failed to line up these rows. Explicit
left-to-right paragraph direction did not correct them. In contrast, the
tested ASCII matches with Hebrew or Arabic context aligned correctly, as did
whole Hebrew or Arabic word matches separated by spaces from Latin context.
Those passing examples do not establish general bidirectional support.

The current calculation sums columns in logical text order; Emacs's
[bidirectional display](https://www.gnu.org/software/emacs/manual/html_node/elisp/Bidirectional-Display.html)
can place the same characters in a different visual order. These measurements
therefore expose a layout assumption, independently of the font-width
disagreements described earlier. Longer right-to-left lines with hidden
context were also probed, but their display positions were not consistently
reliable; no guarantee of bidirectional cropping is made. The audit did not
attempt comprehensive Arabic shaping, vowel marks or explicit direction
controls.

A new batch regression verifies two matches per sample, exact logical line and
match text, unchanged source text, unchanged result text across alignment
changes, and standard Occur jumps to each source match's beginning. All 63
batch tests completed as expected, including the two legacy expected failures.
This passing regression covers data and navigation, not visual alignment.
Bidirectional layout remains a known unresolved issue.

## Remaining verification

Older Emacs versions, terminal Emacs, proportional fonts, and complex emoji sequences have not yet been checked in actual display sessions. Emacs 27.1 is the declared minimum, with runtime compatibility verification still pending. No claim of a full compatibility matrix is made by the current checks.
