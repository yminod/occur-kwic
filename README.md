# occur-kwic

**Align search results by their matches**, so you can compare the surrounding context with less side-to-side eye movement. `occur-kwic` is a KWIC (Key Word In Context) search tool for Emacs, with familiar Occur navigation. If you are looking for a grep-like display with matches lined up vertically, this is the idea.

Each match gets its own result row, even when several matches come from the same source line. The full source line stays in the result buffer; only its display is cropped. Resizing a window reveals or hides context without losing text, and windows of different widths can show the same results independently.

The package is in early development. It searches Emacs buffers using Emacs regular expressions; no external grep program is needed.

## Installation

Load [occur-kwic.el](occur-kwic.el) with `M-x load-file`, then run `M-x occur-kwic` in the buffer you want to search.

For regular use, put this directory on your load path and add an autoload:

```elisp
(add-to-list 'load-path "/path/to/occur-kwic")
(autoload 'occur-kwic "occur-kwic" "Display vertically aligned search matches." t)
```

The declared minimum is Emacs 27.1. Testing so far has used development builds of Emacs 31.1 on macOS / arm64 and Windows / x86_64; older versions still need runtime verification. All dependencies, including `cl-lib`, are built into Emacs.

## Alignment

`occur-kwic-alignment` chooses which part of each match sits at the midpoint of the result window's text area, including the line-number column:

| Value | Position aligned at the window midpoint |
| --- | --- |
| `left` (default) | Start of the match |
| `center` | Center of the match |
| `right` | End of the match |

Here, “left” means aligning the left edges of the matches with each other at the window midpoint.

```elisp
(setq occur-kwic-alignment 'center)
```

Press `a` in a result buffer to change that buffer's alignment. Choosing an alignment also returns expanded rows to KWIC display and resets horizontal scrolling in every window showing the results, even when choosing the current alignment again. Automatic horizontal scrolling is disabled in cropped KWIC display so the cursor cannot shift the aligned rows. Center alignment rounds an odd-width match's start to the right. Long matches remain on one row: the anchor stays fixed and parts outside the available width are hidden.

At extremely narrow widths, there may be too little room for both the line-number prefix and the alignment anchor. Some rows may show a fragment of the match and others only context. A visible match is not guaranteed at those widths. The full text remains intact, and widening the window restores the layout.

## Keys

| Key | Action |
| --- | --- |
| `RET` / `C-c C-c` / mouse-2 | Go to the source match |
| `o` | Go to the source match in another window |
| `C-o` | Display the source match in another window |
| `n` / `p` | Display the next / previous match |
| `M-n` / `M-p` | Move to the next / previous result |
| `g` | Search the source buffer again |
| `a` | Choose left, center, or right alignment |
| `v` | Toggle the current row's full text |
| `s` | Choose a context, match-text, or source-order sort |
| `S` | Toggle case-sensitive sorting and reapply the current sort |
| `r` | Rename the result buffer based on its source |
| `c` | Make an independent snapshot clone |
| `q` | Quit the result window |

Standard `next-error` and `next-error-follow-minor-mode` also work.

Like ordinary Occur, searches reuse the default result buffer. To keep a result
before another search, press `r` to rename it or `c` to make an independent
snapshot. `c` and `M-x clone-buffer` use the same standard cloning support;
`C-u c` prompts for a name. Clones retain point, narrowing, alignment, and
full-line expansion. Closing or refreshing either snapshot leaves the other
usable. Indirect cloning commands are unsupported and rejected because they
share the result text.

Results are read-only. Occur Edit is unsupported: `e`, the editing menu item, and interactive `M-x occur-edit-mode` cannot enable it here. Edit the source buffer and press `g` to refresh. Ordinary Occur buffers retain their editing behavior.

Incremental search (`C-s`, for example) temporarily reveals full text in every window showing the result buffer. After search ends, the final result row stays expanded. Press `v` to return it to KWIC display, or `a` to restore KWIC display with a chosen alignment. Expanded views allow automatic horizontal scrolling according to the global `auto-hscroll-mode` setting. Expansion is shared across views because Emacs's buffer-level invisibility checks also see overlays belonging to other windows.

Copying includes the selected underlying text, including hidden context and original tabs, without the display-only alignment padding.

## Context sorting

Press `s` (`M-x occur-kwic-sort`) and choose a method:

| Method | Sort key |
| --- | --- |
| `after-words` / `before-words` | Up to N word units from the match edge, nearest first |
| `after-characters` / `before-characters` | Up to N characters, nearest to the match first |
| `match` | The matched string |
| `source` | Restore original source order |

Context sorts prompt for a positive N, initially 3, or reuse N from the active
context sort. Word sorts compare the nearest unit first, then the second
only when the first units are equal, and so on. Increasing N refines ties;
rows whose order was already determined by the first unit keep that order.
Each unit's characters are compared from its beginning in their normal order,
including when sorting the preceding context.

Word units follow the source buffer's Emacs word boundaries, starting at the
exact edge of the match. If that edge cuts a word, the unmatched part counts
as the first unit. For example, searching `cat` in `the cats sleep` produces
the following key `("s" "sleep")` for N=2. Searching `\bcat\w*\b` matches
`cats` as a whole and starts that key at `sleep`. A zero-width match inside a
word leaves fragments on both sides. Word sorts can therefore compare both
complete words and word fragments; they do not require a whole-word query.

Character sorts include spaces, punctuation and word fragments. N counts Emacs
characters, including combining characters separately, rather than bytes or
screen columns. Only the preceding comparison key is reversed; displayed and
copied text is preserved. All context stays within the saved accessible source
line, and shorter equal-prefix keys come first. Equal keys always retain
original source order, regardless of previous sorts.

Sorting ignores case by default, independently of search case sensitivity.
Press `S` to toggle this for the result buffer. The mode line shows the active
sort, N and case policy. Sorting preserves the current row, expanded row and
source navigation; widen a narrowed result buffer before sorting it.

`g` re-collects the source and reapplies the chosen sort and case policy.
Clones retain the sort and can be sorted independently. Existing snapshots
keep their saved text and word boundaries even after source edits.

Word boundaries use the source's syntax tables and word-motion settings,
including `subword-mode`. Customize the buffer-local
`occur-kwic-word-motion-function` in the **source** buffer to replace
`forward-word`, then refresh the results. A replacement accepts a signed word
count, moves forward to word ends and backward to word beginnings, returns
non-nil after traversing a word and nil when no further word exists, respects
narrowing, and does not edit text. Forward/backward boundaries must agree.
Results capture and share the ranges once per source line; sorting does not
run the callback again. Regexp `\b` does not necessarily follow customized
motion boundaries, such as the internal boundaries of `subword-mode`.

### Trying word sorting

Open [examples/word-sorting.txt](examples/word-sorting.txt) in `text-mode`.
The short sentences are constructed examples for exploring the controls.
Search with `M-x occur-kwic`, entering `\blook\b` directly in the minibuffer,
then press `s`, choose `after-words`, and enter `1`.

The results group the expressions `look after`, `look at`, and `look for` in
that order. This lets you inspect what follows a word across different uses.
It does not assign grammatical categories or rank expressions by frequency.

Choose `after-words` with N=3 next. The order within each group becomes:

```text
look after young children
look at new maps
look at old maps
look for a job
look for a room
look for new clues
```

With N=1, all `look for` rows share the key `("for")` and retain source order.
With N=3, `("for" "a" "job")` precedes `("for" "a" "room")`, and both
precede `("for" "new" "clues")`. The `look after` and `look at` groups
remain ahead of the `look for` group.

For the preceding side, search `\bevidence\b` and select `before-words`, N=1.
Results group `no evidence`, `strong evidence` (two rows), and `weak evidence`.
Each preceding word is compared from its beginning; its letters stay in their
ordinary order. Preceding character sorts instead compare the nearest
character first, starting at word endings. Following word and character sorts
can look similar when the character window contains enough text, but word
counts use word boundaries and skip separators.

For a partial query such as `ac`, the preceding first unit can be a fragment
of the word containing the match or a complete word before it. Brackets below
mark the matched text:

| Text | `before-words`, N=1 key (ignoring case) |
| --- | --- |
| `callb[ac]k` | `callb` |
| `can [ac]cumulate` | `can` |
| `Char[ac]ter` | `char` |

These sort in the order shown. N counts word units; their contents are still
compared as strings. The text between the match and a word boundary is kept
in the key, even when it is only part of a word.

The current display highlights the match but does not mark the context keys.
Start with N=1 and a whole-word query when checking the behavior; a partial
query can make a word fragment the first key, as described above.

## Search behavior and scope

- Search respects the source buffer's narrowing. An active region further restricts the search. Context outside those bounds is not included, even when a boundary falls inside a line.
- A region does not restart line numbering. As in ordinary Occur, numbers are relative to the source buffer's accessible beginning before applying the region. Field text properties, such as prompt/input boundaries in shell buffers, do not split line context or count as newlines.
- Case sensitivity follows `case-fold-search` and `search-upper-case`, as in ordinary Occur.
- Results initially follow source order, with one row per non-overlapping match. Use `s` to sort them by context or matched text.
- Zero-width matches use a display-only `|` marker. An empty regexp is rejected.
- An actual match containing a newline raises an error and leaves previous results intact. Invalid regexps also leave previous results intact.
- `g` tracks the original region with markers and applies the source buffer's current narrowing. If the two ranges no longer overlap, there are no matches. Source edits are not automatically synchronized into results.
- Context-line and collection prefix arguments, and searches across multiple buffers, are outside the initial scope.

Tabs are displayed using the source's `tab-width`, measured from the start of the accessible source line. If narrowing begins inside a line, expansion starts at that accessible boundary.

`C-g` can interrupt a search. Cancellation or an error during match collection leaves previous results intact. Once result construction or its first layout has begun, failure discards that result buffer, including during `g`; the previous contents of a buffer being rebuilt are not restored. Other result buffers and clones remain intact. A failed clone operation discards only the incomplete clone.

Large results can be surprising: each match repeats its entire source line in
the result text. When the estimated result rows exceed **10 MiB**, occur-kwic
warns that Emacs may become slow or run out of memory and asks whether to
continue. Choosing no, or pressing `C-g`, cancels the search and preserves
previous results. Choosing yes continues the complete search without another
size confirmation until the next search or `g`.

Customize `occur-kwic-output-size-warning-threshold` to change this threshold
in bytes; `nil` disables the warning. For example, to warn at 20 MiB:

```elisp
(setq occur-kwic-output-size-warning-threshold (* 20 1024 1024))
```

The estimate counts repeated line text, line-number prefixes and newlines in
Emacs's internal multibyte representation. It excludes the header and the
additional memory for markers, text properties, column tables and overlays.
This is a confirmation threshold, not a safe memory limit or a final-size
prediction: output can keep growing after confirmation. Batch searches signal
an error at the threshold instead of prompting; adjust or disable the option
explicitly to continue them.

Alignment uses Emacs's logical display columns. These can disagree with actual glyph widths when fonts, Unicode East Asian Width (including ambiguous-width characters), and Emacs's language and character-width settings do not agree. Matches may then fail to line up even with monospaced fonts, and differences can accumulate across context characters. This affects display only; source text and stored result text remain intact. occur-kwic does not check or automatically adjust font or character-width settings. Pixel-perfect positioning with proportional fonts or complex emoji sequences is also outside its scope.

Bidirectional text, including Hebrew and Arabic, has a separate known layout
problem: the current calculation follows logical character order, whereas
Emacs can reorder characters for display. Matches can therefore fail to align,
even with equal-width glyphs. Search, stored text and source navigation have
passed basic Hebrew and Arabic tests, but reliable alignment and cropping of
bidirectional text are not currently supported. Fixing a paragraph's direction
to left-to-right does not resolve reordering within a right-to-left run.

See the [RTL and concordance research notes](docs/rtl-research.md) for measured
layout experiments. Context sorting follows logical before/after positions
and does not resolve the bidi display limitation.

Use `occur-kwic-hook` for actions after a successful search. Mode initialization runs the parent `occur-mode-hook` and `occur-kwic-mode-hook`. The ordinary `occur-hook` is not run, since some of its functions assume ordinary line-based Occur output.

## Development

The test entry points need Emacs and either a POSIX shell or PowerShell. GNU Make is optional. Run these commands from this repository.

On macOS, Linux, or another POSIX environment:

```sh
./scripts/test.sh
./scripts/test.sh --test-only
EMACS='/path/with spaces/to/emacs' ./scripts/test.sh
```

The shell script uses POSIX `sh` syntax and works with macOS's system shell and Bash 3.2; it does not require a newer Bash.

On Windows, or any system with PowerShell installed:

```powershell
pwsh -NoProfile -File ./scripts/test.ps1
pwsh -NoProfile -File ./scripts/test.ps1 -TestOnly
pwsh -NoProfile -File ./scripts/test.ps1 -Emacs 'C:\Program Files\Emacs\bin\emacs.exe'
```

Use `emacs.exe`, rather than `runemacs.exe`, for batch checks on Windows. Both entry points accept an `EMACS` environment variable; PowerShell's `-Emacs` parameter overrides it. They locate the repository relative to the script, so they can also be invoked by path from another working directory. The process exit code is zero on success and nonzero on failure.

Both scripts call the same Emacs Lisp runner. You can also invoke it directly:

```sh
emacs -Q --batch -l scripts/run-tests.el
emacs -Q --batch -l scripts/run-tests.el --test-only
```

The existing Make targets use the POSIX entry point:

```sh
make check
make test                       # ERT tests only
make check EMACS=/path/to/emacs  # Use a different Emacs
```

The default run checks parentheses, loads both implementations, byte-compiles with warnings treated as errors, and runs ERT. Compilation uses a temporary directory and removes its artifacts. Test-only runs skip source checks and compilation.

The batch suite has 76 tests: 59 passing tests for `occur-kwic`, plus 17 legacy
characterization tests with 15 passes and 2 expected failures. The expected
failures record legacy tab alignment and zero-width search progress. A
successful run reports `76 results as expected, 0 unexpected` and
`2 expected failures`.

Five additional GUI tests check actual pixel positions after redisplay,
interactive alignment and sorting, horizontal scrolling, multiple windows,
resizing, naming a clone with `C-u c`, and combining-character alignment with
the source visible or hidden. Run them in a fresh GUI Emacs process, without
`--batch`:

```sh
emacs -Q -l scripts/run-gui-tests.el
```

The runner exits that Emacs process when finished, with exit code 0 on success and nonzero on failure. It writes its log to `occur-kwic-gui-tests.log` in Emacs's temporary directory; set the `OCCUR_KWIC_GUI_TEST_LOG` environment variable to choose another log path. These tests assume the fresh frame's default fixed-width font. They have passed on Windows; rerunning them on macOS remains pending.

- [Implementation tests](test/occur-kwic-tests.el): alignment, full-text retention, search, navigation, sorting and word boundaries, refresh, cloning, and disabled editing.
- [GUI tests](test/occur-kwic-gui-tests.el): alignment coordinates after actual redisplay, including sorting and scrolling regressions.
- [Legacy tests](test/eyegrep-tests.el): preserve observed strings, column positions, search bounds, and source targets. Legacy rounding and fixed offsets are comparison data rather than requirements for the redesign.
- [Design](docs/occur-kwic-design.md): behavior and implementation decisions.
- [Layout audit](docs/layout-audit.md): findings about the original implementation.
- [Validation record](docs/implementation-checks.md): automated checks and GUI measurements.
- [Concordance sorting research](docs/concordance-sorting-research.md): documented uses, scope decisions, and Emacs word-boundary and row-sorting probes.

## History and license

`occur-kwic` grew out of [eyegrep.el](legacy/eyegrep.el), a personal tool I have used since around 2010 for displaying centered grep-like results in Emacs. The legacy file is preserved unchanged as a comparison baseline, with a short [history](legacy/README.md).

GNU GPL version 3 or later (GPL-3+). See [COPYING](COPYING).
