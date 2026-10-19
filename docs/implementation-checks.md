# Initial implementation validation

Recorded on 2026-10-20 for [occur-kwic.el](../occur-kwic.el). The legacy implementation remains unchanged.

## Automated checks

`make check` checked parentheses, loading, and byte compilation with warnings treated as errors for both implementations, then ran 39 ERT tests. All 22 new-implementation tests passed. Of the 17 legacy tests, two were expected failures documenting tab alignment and zero-width search progress. There were no unexpected results.

The new tests observe result text, window-specific display properties, source markers, and ordinary Occur navigation. They do not simply duplicate the layout formula as their expected-value calculation.

## GUI alignment and resizing

GUI checks used a dedicated frame and disposable buffers in a local development build of Emacs 31.1 on macOS / arm64. Existing key bindings and user settings were left unchanged. Lines containing tabs, Japanese text, and long context were displayed in two windows of different widths. Actual coordinates from `posn-at-point` and screenshots were inspected.

The frame's canonical character width was 13 pixels. With text-area widths of 39 and 65 columns, left-aligned matches `X`, `YY`, and `ZZZ` all started at 247 and 416 pixels respectively, relative to their windows. Right alignment made their ends coincide. Center alignment showed the expected half-column odd/even rounding difference.

After resizing to 44 and 60 columns, all match starts moved to 286 and 390 pixels respectively. The layout function was not called manually after resizing; redisplay hooks updated the views.

## Searching hidden context

An initial implementation revealed text only in the selected window. Invisible overlays left in the other window affected Emacs's buffer-level search checks: searching for a visibly displayed `HIDDEN_START` failed.

The implementation now reveals all rows in every view during incremental search and leaves the final result row expanded afterward. Tests check buffer-level `invisible-p` as well as window-specific display properties. After the fix, ordinary GUI incremental search found and highlighted `HIDDEN_START`. The `v` command restores KWIC display.

## Author trial and extremely narrow windows

The author reported no problems during a trial. Near the minimum window width, some rows retained part of the match while others retained only context. The author did not regard that difference as meaningful when all rows were already incomplete.

When the midpoint overlaps the line-number area, the same cropping rules can leave different fragments depending on match position, match width, and context length. No special rule was added to force a uniform appearance or prioritize matches at those widths. This is documented as a display limitation.

A regression test exercises three-digit line numbers with all three alignments at widths 3, 4, 5, 6, 8, 10, and 12. It verifies that layout does not error, full text and source markers survive, and widening restores ordinary centered anchors in left alignment. Exact tiny-width fragments are not fixed as part of the interface. This test did not change the implementation's behavior.

## Remaining verification

Older Emacs versions, terminal Emacs, proportional fonts, and complex emoji sequences have not yet been checked in actual display sessions. Emacs 27.1 is the declared minimum, with runtime compatibility verification still pending. No claim of a full compatibility matrix is made by the current checks.
