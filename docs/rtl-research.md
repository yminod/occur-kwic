# RTL layout and lightweight concordance features

Research notes, 2026-10-20. These are implementation candidates, not a new
support guarantee. Production layout and source-order output remain unchanged.
The intended scope is an Occur-like tool with a few concordancer operations,
using Emacs facilities by default and allowing optional external metadata.

## Recommendation

Keep context extraction and sorting in logical reading order, independent of
screen coordinates. Add lightweight context sorting before committing to a
general bidi layout implementation. There is a small RTL coordinate correction
worth further investigation, but it is insufficient for general mixed text.
Neither that correction nor a field-based renderer is ready for production.

The existing full-line view (`v`, also used during isearch) remains a useful
way to inspect context without KWIC's crop. It does not align RTL matches or
guarantee that a match in a long line is initially on screen. Source navigation
remains available. This fallback is not a claim of full bidi support.

## Three different meanings of position

| Layer | Meaning | Suitable operations |
| --- | --- | --- |
| Source snapshot | Logical characters and match offsets | Search, context, sorting, copying |
| Metadata | Word spans, context keys, stable match identity | Standard Emacs extraction; optional external enrichment |
| Window view | Visual glyph order and physical coordinates | Alignment, clipping, padding |

Use **before/after** for context and **left/right** for physical placement.
For RTL text, the context logically before a match can appear to its right.
Choosing right-context sorting by screen position would make sorting depend
on bidi context, cropping and potentially window width.

The [Emacs bidi reference][bidi] explains that logical offsets need not map
monotonically to screen positions. It also documents native visual motion,
field separators and atomic display replacements. These are useful primitives,
but none is a ready-made KWIC layout function.

## Ordinary RTL editing and standard Occur

Normal RTL editing keeps `bidi-display-reordering` enabled (default `t`).
Setting it to nil disables logical-to-visual reordering; it does not select
RTL editing. Its built-in variable documentation explicitly limits that setting
to display debugging and says it is unsupported in normal sessions.
`bidi-paragraph-direction` instead selects the paragraph's base direction:
nil means automatic detection, while `right-to-left` forces RTL paragraphs.

In a simple RTL paragraph, typing advances from the right margin toward the
left. At the left margin a continued line resumes at the right of the next
screen row. With truncation and automatic horizontal scrolling, further
leftward progress can instead move displayed text rightward. Digits and Latin
runs retain LTR ordering; point movement therefore is not a uniform mirror
image of an LTR buffer. `C-f`/`C-b` follow logical order. See the
[editing manual][editing] and [horizontal scrolling reference][hscroll].

Standard `occur` searches logical text, copies matching source lines with
line-number prefixes, and leaves display ordering to Emacs. Inspection of
Emacs 31.1's `occur-mode`, `occur-engine` and `occur-engine-line` in `replace.el`
found no transfer of source-local bidi settings and no KWIC coordinate layout.
A fresh `-Q` batch experiment with Hebrew source text confirmed:

| Source paragraph setting | Source effective direction | Occur setting | Result row effective direction |
| --- | --- | --- | --- |
| nil | RTL | nil | LTR |
| `right-to-left` | RTL | nil | LTR |
| `left-to-right` | LTR | nil | LTR |

The result retained `bidi-display-reordering=t`. Its English header supplied
the first strong direction, and no empty line separated it from the result
row. RTL runs within that LTR paragraph still reorder. Thus standard Occur
does not necessarily reproduce the source paragraph's placement or surrounding
bidi context, even though it retains logical text and source targets. Custom
hooks, paragraph boundaries and formatting controls can change these results.

## Comparison with OSS concordancers

KonText provides a concrete example of three-column rendering rather than
padding a continuous text line. In the inspected official repository commit
`c13cd683aed0034c29a1a517888abd421126d23a`, `TextKwicMode` creates three HTML
table cells for logical before/keyword/after. When `textDirectionRTL` is true,
it reverses the cell array and exchanges the context alignment classes.
CSS right-aligns the physical left context, left-aligns the physical right
context, and centers the keyword. These are table cells, not three independent
editor windows. See the [view code][kontext-view] and [styles][kontext-style].

Thus the table renderer handles the outer alignment and width of each field;
the application does not need to sum character columns to place a substring
inside an otherwise continuous line. KonText's view also works with tokens
and token identifiers, which differs from splitting arbitrary regexp matches
at character offsets inside words. This code inspection is not an independent
validation of KonText's behavior for every mixed-direction case.

CQPweb's [administrator manual][cqpweb-manual] documents per-corpus
directionality settings (page 52) and HTML direction control for RTL corpora
(page 89). It explicitly notes potential interactions between inserted markup
and surrounding text direction. This is documentation evidence, not a source
audit or a claim that its implementation can be copied into Emacs.

Three columns do not by themselves preserve the appearance of an original
mixed-direction sentence. Rychly and Kovar's 2007 paper,
[Displaying Bidirectional Text Concordances in KWIC format][kwic-paper],
describes this exact problem in Manatee/Bonito: splitting a concordance into
keyword and two contexts requires additional treatment of direction boundaries
and neutral characters. The paper is historical evidence of the problem, not
a description of current KonText or a recommendation to reproduce its older
algorithm unchanged.

The transferable lesson is to distinguish a concordance presented as fields
from an intact source line with an aligned substring. Three-field presentation
remains an option worth investigating, but adopting it would change the view's
contract and would still require boundary and shaping checks. Existing tools
are useful references for that decision; they do not establish that the present
two-overlay crop model can support general bidi with a small correction.

## Reproducible layout experiments

[scripts/probe-rtl.el](../scripts/probe-rtl.el) runs in a fresh GUI Emacs and
exits that process. It scans actual pixels with `posn-at-x-y`, identifying
either buffer match positions or the replacement match string. It records
the left edge, exclusive right edge, number of separate visible match spans,
and the logical offsets encountered from left to right. Offset listings for
replacement strings identify their underlying buffer positions, not individual
characters inside those strings.

```sh
emacs -Q -l scripts/probe-rtl.el
```

Output defaults to `occur-kwic-rtl-probe.tsv` in Emacs's temporary directory;
`OCCUR_KWIC_RTL_PROBE_LOG` overrides the path. Measurements are exploratory,
not passing assertions of RTL support. The probe verifies that experimental
display changes preserve the underlying result text.

The samples include Hebrew, Arabic, numbers in Hebrew context, a digit match,
a match crossing Latin/Hebrew boundaries, substrings inside words, and long
Hebrew context. Each is measured with all three alignments under five modes:

| Mode | Experiment |
| --- | --- |
| `current` | Unmodified occur-kwic layout |
| `ltr` | Same layout with explicit LTR paragraph direction |
| `mirror` | Reverse cumulative columns and match offsets for layout, then map crop offsets back; retain original text |
| `fields` | Render logical before/match/after as three separate overlay display strings, retaining original text |
| `expanded` | Full-line display with LTR paragraph direction, without KWIC padding/cropping |

Windows Emacs 31.1, build 2026-09-17, default Courier New, 80 columns with
eight-pixel columns reproduced the following left-edge measurements. Left
alignment's target was x=320. Each cell lists the two result rows.

| Sample | Current | Forced LTR | Mirrored columns | Separate fields |
| --- | --- | --- | --- | --- |
| Hebrew word | 320 / 280 | 320 / 280 | 320 / 320 | 320 / 320 |
| Arabic word | 312 / 264 | 312 / 264 | 312 / 320 | 320 / 312 |
| Digit match in Hebrew | 312 / 304 | 312 / 304 | 312 / 296 | 320 / 320 |
| Match crossing Latin/Hebrew | 320 / 320 | 320 / 320 | 296 / 312 | 320 / 320 |
| Hebrew substring | 344 / 320 | 344 / 320 | 320 / 320 | 320 / 320 |
| Long Hebrew context | 296 / 296 | 296 / 296 | 320 / 320 | 320 / 320 |

### Mirroring: small but restricted

Mirroring fixes the tested Hebrew word, substring and long-context samples,
including center and right alignment. It changes only the calculation and
which logical ends are hidden, preserving the native reading order. This is
the most promising small experiment for a deliberately restricted layout.

It is not a general RTL detector or a bidi algorithm. A Latin/Hebrew match
fails, and digits have their own LTR runs even inside RTL text. Arabic rows
also retain an eight-pixel discrepancy: character-column sums do not account
for all shaping/composition advances. That width issue must be distinguished
from the reordering issue. This probe does not establish Arabic shaping
correctness or cluster-safe clipping.

### Separate fields: a different presentation contract

The field prototype is compact and aligns the tested Hebrew samples. However,
it places logical before/match/after fields in LTR column order and prevents
reordering across their boundaries. The mixed match `c אב` in `abc אבג def`
occupies **two** visual spans in the native full-line view, but **one** in the
field view. The latter changes how the original sentence is displayed.
It also retains the Arabic width discrepancy in a different row.

Splitting within an Arabic word additionally requires checking joining and
ligatures. Directional isolation is not automatically harmless to joining;
see [Unicode's discussion of cursive joining][joining]. A word-boundary-only
field view might be worth evaluating later, if explicitly presented as
concordance columns. It should not silently replace natural full-line display
for arbitrary regexp matches.

### Native visual coordinates: investigate without a custom UBA

`move-point-visually` and position queries offer a possible Emacs-only route.
However, a match can have multiple visual spans. The present layout returns
one logical interval `(START END PADDING)` and uses two hiding overlays;
visual cropping cannot generally be expressed that way. A visual map would
need multiple intervals, shaping-aware edges, preservation of bidi context,
and checks that hiding characters does not change the computed order.

Measure this route separately before adopting it. It must work without
requiring every result row to be on screen, preserve each window's independent
layout, and stay responsive on long lines with many matches. Repeated
redisplay/coordinate correction for every row is not an established lightweight
solution. No custom Unicode bidi or shaping implementation is proposed.

The optional `OCCUR_KWIC_RTL_PROBE_WALK=1` experiment times a full native
visual walk over `x ` followed by repeated Hebrew letters and a newline.
Redisplay occurs before timing. On the same Windows build, one pass measured:

| Characters including prefix/newline | Visited positions | Time |
| ---: | ---: | ---: |
| 53 | 53 | 2.0 ms |
| 103 | 103 | 7.3 ms |
| 203 | 203 | 26.4 ms |

This small, single-run sample suggests roughly quadratic scaling for this
workload, not a general complexity guarantee. In particular, calling a native
primitive does not establish that building a full visual map for every result
and every resize is cheap. Benchmark longer distinct lines and sharing between
matches before choosing this approach. The walk does not implement clipping
or validate preservation of bidi context after clipping.

## Concordance sorting within the existing scope

Character-context keys can be extracted from the immutable line text and
match offsets. Define N as Emacs characters, not bytes, display columns or
grapheme clusters. Combining characters therefore count individually. Restrict
context to the accessible source line already retained in the snapshot; crossing
newlines would be an explicit later scope change.

Word-context keys should use Emacs word motion in the **source's** context,
not Occur mode's syntax table or a whitespace split. [Word motion][words]
uses syntax tables and script boundaries, with mode-specific boundary functions
where configured. Bind `inhibit-field-text-motion` consistently with collection
and respect narrowing/region limits. Decide explicitly whether a match inside
a word contributes a partial adjacent word or starts with the next complete
word. This is an extraction policy, not a bidi display decision.

For concordance-style sorting, a useful candidate is a tuple of adjacent
words, nearest first. Before-context sorting compares the preceding word,
then the second preceding word; after-context sorting compares the next word,
then the second next word. Keep characters **within each word** in logical
order. Do not reverse RTL words to construct keys. A literal N-character
substring sort and a nearest-character-first sort are distinct operations;
the eventual interface should state which one it provides.

Start with a deterministic built-in comparator and stable ties in original
source order. Locale-aware comparison could be optional, but its ordering
varies by platform and locale; [Emacs documents those dependencies][collation].
Neither choice provides morphological analysis or dictionary order for every
language. External key enrichment can address such needs independently.

### Metadata and snapshot lifetime

Compute requested keys once per entry before sorting, not during comparison
and not on each window resize. If word boundaries are collected, share their
immutable offsets between matches on the same source line, as line text and
column vectors already are. Capturing boundaries in the source during search
avoids applying changed source text or changed mode settings to an old
snapshot. The cost of eager word-boundary capture versus on-demand extraction
from a sufficiently complete snapshot still needs measurement and a policy.

An eventual key-provider function can accept immutable snapshot context and
return keys keyed by stable per-match identifiers. Built-in extraction is the
default provider; an optional external adapter may enrich those keys. Include
the requested context specification and snapshot generation when associating
results. Repeated matches on one line must remain distinguishable. Treat
returned keys as data; no external dependency is needed in the core renderer.
There is no need to freeze a public provider API during this layout research.

### Existing invariants that sorting must preserve

Do not simply reorder `occur-kwic--entries` or call a text sorting command:

- Entry row positions are integers. Reordering text requires rebuilding their
  row/text offsets and Occur properties while keeping source targets correct.
- Marker cleanup deliberately follows reverse creation order to avoid
  quadratic unlinking. Cloning also creates markers in entry order. Preserve
  canonical ownership/creation order separately from display order.
- Prefix width currently uses the last source-ordered entry's line number.
  A sorted last row need not have the largest line number.
- Equal-key rows need a stable source-order tie; a source-order command should
  restore the original sequence. Refresh, cloning, point and expanded-row
  selection need explicit behavior after sorting.

These are small, concrete changes that belong to a sorting implementation;
none requires adopting a new bidi renderer or linguistic analysis framework.

## Adoption criteria and current outcome

The subsequent scope decision is to leave post-redisplay measurement/correction
out of the implementation: even a successful static experiment would leave
substantial update and window-state management. The current investigation moves
to [lightweight concordance sorting](concordance-sorting-research.md), using
Emacs/user word boundaries independently of display direction.

A future RTL implementation should preserve search/copy/navigation semantics,
define physical anchors for fragmented matches, preserve readable context and
joining, and cover narrow/long rows, zero-width matches, tabs, combining marks,
direction controls, multiple windows, resizing, isearch and cloning. Prefer
native Emacs rendering and measure costs per distinct source line where possible.

For now, retain the known limitation and the existing full-line inspection
path. Keep mirrored columns as a restricted prototype and field rendering as
a possible explicit concordance presentation. Sorting keys can proceed in
logical order without waiting for general bidi alignment. No production RTL
or sorting behavior was changed by this research.

The existing batch suite still reports 63 results as expected, zero unexpected,
including two expected legacy failures. This validates existing behavior;
it is separate from the exploratory display measurements above. The GUI probe
completed all eight sample groups, five modes and three alignments, and its
source passed parentheses checking and byte compilation with warnings treated
as errors. Other Emacs versions and terminal display remain unverified.

[bidi]: https://www.gnu.org/software/emacs/manual/html_node/elisp/Bidirectional-Display.html
[editing]: https://www.gnu.org/software/emacs/manual/html_node/emacs/Bidirectional-Editing.html
[hscroll]: https://www.gnu.org/software/emacs/manual/html_node/elisp/Horizontal-Scrolling.html
[words]: https://www.gnu.org/software/emacs/manual/html_node/elisp/Word-Motion.html
[joining]: https://www.unicode.org/versions/Unicode17.0.0/core-spec/chapter-23/
[collation]: https://www.gnu.org/software/emacs/manual/html_node/elisp/Text-Comparison.html
[kontext-view]: https://github.com/czcorpus/kontext/blob/c13cd683aed0034c29a1a517888abd421126d23a/public/files/js/views/concordance/lines/index.tsx#L464
[kontext-style]: https://github.com/czcorpus/kontext/blob/c13cd683aed0034c29a1a517888abd421126d23a/public/files/js/views/concordance/lines/style.tsx#L216
[cqpweb-manual]: https://cwb.sourceforge.io/files/CQPwebAdminManual.pdf
[kwic-paper]: https://www.sketchengine.eu/bibliography-of-sketch-engine/attachment/displaying_bidirectional_text_2007/
