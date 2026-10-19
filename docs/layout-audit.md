# Legacy eyegrep layout audit

Recorded on 2026-10-20. The original [eyegrep.el](../eyegrep.el) is unchanged. The author's experience of stable alignment in normal use serves as a comparison baseline for the redesign.

## Method and scope

The original command was run in batch Emacs 31.1 with a controlled calling-window text width. Generated result rows and display columns were inspected. These checks concern column arithmetic and output, not GUI pixel positions or every font's rendering.

The ordinary-character layout formula was also swept over text widths from 20 to 120 columns, line numbers from one to five digits, and positive match widths that fit within the context area. At a fixed window width and prefix width, match centers differed by at most half a column. The odd/even difference is consistent with rounding to integer columns.

## Ordinary characters

- At a text width of 80 columns, ASCII matches of widths 1, 2, and 3 had centers at columns 40.5, 40.0, and 40.5.
- At a text width of 30 columns, `X` following different lengths of ordinary full-width text started at column 15 in both cases.
- With three-digit line numbers, a two-column match in an 80-column window had its center at column 41. This is a fixed bias from the geometric midpoint, separate from stability across rows.

These observations support the author's report of stable ordinary-character alignment. They do not justify treating the original layout formula as generally incorrect.

## Tabs in the left context

At a text width of 30 columns, searching for `X` with the default `tab-width` compared these lines:

```text
a<TAB>X tail
X tail
```

`string-width` measured the generated prefix before `X` as 15 columns in both rows. In the actual result buffer, `current-column` reported 8 and 15. A tab's standalone width differs from its advance to the next tab stop at a particular position.

The author confirmed that tabs had not been considered. The redesign retains original tabs in the underlying text and displays their source-line expansion, using the source's `tab-width` from the start of the accessible line.

## Oversized matches

A 40-column match in a 30-column window produced a 42-column result row, with the match starting at column 2. The legacy code neither crops the match itself nor centers it in this case.

The redesign keeps the chosen alignment anchor fixed and clips the visible portion without wrapping. In left alignment, the match therefore has roughly the right half of the window available.

## Zero-width matches

Searching a nonempty buffer for `^` repeatedly left `re-search-forward` at position 1. A separate process running the original command did not finish within three seconds and was stopped. Rejecting an empty regexp does not prevent this search-loop problem.

The new implementation explicitly advances after a zero-width match and marks its position with a display-only `|`.

## Window width

`window-body-width` already excludes fringes and similar non-text areas. The legacy comment describing a further two-column subtraction as fringe allowance does not match that API's definition. The redesign distinguishes the text area from the final column reserved for Emacs's truncation indicator.

## References

- [GNU Emacs Lisp Reference Manual: Size of Displayed Text](https://www.gnu.org/software/emacs/manual/html_node/elisp/Size-of-Displayed-Text.html)
- [GNU Emacs Lisp Reference Manual: Window Sizes](https://www.gnu.org/software/emacs/manual/html_node/elisp/Window-Sizes.html)
