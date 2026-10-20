# Lightweight concordance sorting

Research and initial implementation decisions, 2026-10-20. Context, match-text
and source-order sorting are now implemented; see the [user guide][guide] and
[validation record][validation]. The goal is useful concordance operations
within an Occur-like tool, using Emacs facilities rather than a corpus analysis
platform. The comparisons below retain the reasoning behind the scope.

The user's requirement is to use Emacs word boundaries, including meaningful
user customizations. Space-separated prose is a convenient starting point for
examples, not a restriction to particular languages or a whitespace tokenizer.
General bidi alignment remains outside the supported layout scope.

## What sorting is used for

The main benefit is putting comparable contexts next to each other so people
can inspect recurring expressions and grammatical patterns. This fits the
existing aligned display and navigation back to the source.

Kilgarriff and Kosem's [Corpus tools for lexicographers][lexicography], section
3.4.1, describes the typical choices as the first word before, first word after,
and the matched form itself. Sorting after a verb brings patterns such as
`argue about`, `argue for`, and `argue that` together. Sorting before an English
noun helps compare modifiers and preceding verbs. Match-form sorting separates
different surface forms returned by a broader query. Looking farther from the
match can reveal additional patterns.

This is evidence from documented workflows and examples, not a measurement of
how often users invoke each command. The priorities below are a design judgment
based on those uses and occur-kwic's scope.

| Tool or guide | Relevant documented behavior |
| --- | --- |
| [AntConc manual][antconc], KWIC section | Before/after and match-based presets; up to three custom keys; value or frequency ordering |
| [University of Wuerzburg tutorial][wuerzburg] | Explains sorting by the first word after a match, then the second, to make analysis easier |
| [Sketch Engine guide][sketch-guide] | Quick sorting by the match and the first following token; sorting, filtering and frequency analysis are separate operations |
| [CQP manual][cqp], sections 2.9 and 3.3 | Successive preceding/following token keys, token order versus character reversal, and restoration of corpus order |
| [NINJAL NPCMJ tutorial][npcmj], slides 16–17 | Source, preceding-context and following-context order, with a Japanese-text example |

## Selected first scope

| Operation | Concrete use | Priority |
| --- | --- | --- |
| Following N words | Compare continuations, complements and recurring phrases | First scope |
| Preceding N words | Compare modifiers, preceding verbs and other lead-ins | First scope |
| Matched string | Group different strings returned by a regexp or case-insensitive query | First scope; little benefit if every matched string is identical |
| Original source order | Return to the ordinary Occur reading/navigation sequence | Required alongside sorting |
| Before/after N characters | Compare spelling fragments, punctuation or contexts where word rules are unhelpful | First scope, following the review below |
| Independent positions or mixed-side keys | Compare the second following word first, or preceding and following words together | Later, if use warrants a larger interface |
| Frequency order of context groups | Bring repeated patterns to the top | Later; feasible, but requires grouping/count semantics |
| Lemma/POS, metadata or example-quality order | Compare linguistic categories or document properties | Optional enrichment; no analyzer required initially |

Prefer before/after presets over a multi-key configuration editor initially.
A positive N selects how many adjacent words participate; N=1 covers the
simplest use, while N=3 covers a three-level arrangement. The `s` command starts
with N=3 and reuses N from the active context sort. Source order remains the
default before a user requests a sort; `S` toggles sort case folding.

## Key semantics

Use logical **before/after**, independent of physical display direction and
window cropping. For N=3, compare tuples:

- After: `(next-word, second-next-word, third-next-word)`.
- Before: `(previous-word, second-previous-word, third-previous-word)`.

Keep each word's characters in reading order. Reversing the entire preceding
substring would also reverse characters inside words and gives a different
operation. Comparing the preceding phrase in its ordinary forward order would
instead prioritize its farthest word.

For example, before `MATCH`, `alpha zebra` produces `("zebra" "alpha")`, and
`zeta apple` produces `("apple" "zeta")`. The latter comes first because the
adjacent word `apple` sorts before `zebra`.

These synthetic rows illustrate a three-word after sort; they are not corpus
data or a frequency finding:

```text
They argue about the cost.
They argue for a change.
They argue for the proposal.
They argue for the proposal.
They argue that it works.
```

Within the `for` group, the second word compares `a` with `the`. Identical
keys tie in original source order, regardless of previous sorts.

Extraction and comparison policy accepted in discussion:

- Use the source's Emacs word motion, respecting syntax tables and
  `find-word-boundary-function-table`. Do not substitute whitespace splitting
  or a private tokenizer. [Emacs documents these customization points][word-motion].
- Keep context within the accessible source-line snapshot. Do not expose
  context excluded by narrowing/region limits or silently add cross-line text.
- Include the unmatched part of a word intersecting a regexp match as the
  first context unit. A prefix contributes before the match, a suffix after
  it. A zero-width match inside a word leaves fragments on both sides. Word
  spans at accessible boundaries are limited to the accessible text. This
  supersedes the earlier exclusion candidate discussed below.
- A shorter tuple precedes a longer one when its components are an equal
  prefix. Word rules determine punctuation handling; there is no additional
  punctuation-removal pipeline or automatic sentence-boundary detection.
- Case-insensitive keys help group ordinary prose. Keep the choice independent
  of search case sensitivity and allow case-sensitive comparison. Start with
  deterministic Emacs string comparison; locale collation, accent folding and
  morphological normalization are separate options.
- Preserve source/result text. Normalization and reordered words belong only
  to keys, not to text users read or copy.

Honoring Emacs/user boundaries does not promise linguistic tokenization for
every language. Their usefulness remains under the user's control.

The user also accepted retaining the requested sort across refresh: `g`
recollects under the source's current settings and reapplies that sort. Extra
options for edge-case policies are not necessary for the lightweight use case.

The buffer-local `occur-kwic-word-motion-function` defaults to `forward-word` and can
be replaced with a function accepting a signed word count. Positive movement
ends at a following word end; negative movement ends at a preceding word start.
It follows `forward-word`'s return convention: non-nil after traversing a word,
nil when no further word exists. Copying the function value does not
copy the source's syntax tables or other mode-local state. Execute it in the
source context during collection and save the resulting spans, rather than
executing it under Occur-mode rules. Lack of forward progress or inconsistent
backward boundaries signals an error, preserving old results during collection.

## Follow-up: partial matches and character sorting

Documentation review, 2026-10-20. These findings distinguish documented
interfaces from observed runtime behavior; no third-party binaries were run.

### Words intersecting the match

| Tool | What the documentation establishes | Implication and limit |
| --- | --- | --- |
| CQP/CQPweb | The [CQP manual][cqp], sections 3.3 and 2.7, defines matches as token sequences and context offsets outside their first/last tokens | Matched tokens do not become context fragments. This is compatible with excluding intersecting words, but arbitrary character matches inside a token are not the same input model |
| Sketch Engine | [CQL basics][sketch-cql] searches tokens, including tokens whose attributes match a prefix/suffix regexp; the concordance guide sorts by neighboring tokens | A query for a word beginning with a prefix returns the token. It does not document treating the unmatched suffix as the next context word |
| AntConc 4.4.1 | The [manual][antconc] distinguishes token-level Regex from document-level Full Regex and describes L/R token sort keys | The exact context-key treatment of a Full Regex hit ending inside a token is not specified. Do not infer its behavior from the token-level mode |
| WordSmith 9 | [Search-word syntax][wordsmith-search] defaults to whole-word matching; `book*` finds `book`, `books`, `booking`, etc. | Its ordinary wildcard workflow includes the word ending in the match. It does not establish every partial-regexp sorting edge case |

The review found no prevalent contrary convention that required changing the
initial exclusion policy. This is not proof that all major tools implement
the identical rule for arbitrary substring hits. In particular, AntConc's Full
Regex edge case remains unverified. Retaining exclusion was the initial
recommendation, not a claim of universal compatibility. The subsequent
control-based review changed that recommendation.

### Decision review: control through regexp boundaries

The user subsequently asked to assess fragment inclusion versus exclusion by
how well a search author can control the resulting word keys. The user then
accepted remainder inclusion for a working implementation and UX trial.

For the regexp `cat`, with the brackets marking the exact match:

| Source | First following key, include remainder | First following key, exclude intersecting word |
| --- | --- | --- |
| `the [cat]s sleep` | `s` | `sleep` |
| `the [cat]like animals` | `like` | `animals` |
| `the [cat] eats` | `eats` | `eats` |

Including the remainder is naturally understood as starting word motion at
the exact match endpoint. A partial first unit counts as one of N units; on
the preceding side, use the unmatched prefix symmetrically. This would make
fragments inspectable with word keys without a separate extraction option.
Exclusion keeps the immediate surrounding complete words comparable despite
different suffix lengths, while the exact match and alignment stay unchanged.

The regexp boundary assertion `cat\b` restricts the hits: it does not keep
`cats` while skipping its `s` for sorting. A regexp such as `\bcat\w*\b`
instead consumes the whole word, allowing a remainder-including policy to
reach the following complete word, but it changes the matched/highlighted span
and the anchor used by layout. Thus inclusion offers more control through
expanding the regexp **when changing the match span is acceptable**. It is not
a strict replacement for exclusion while preserving the original match span.
Conversely, exclusion discards the suffix as a word key; obtaining it requires
a character key or another extraction choice. Neither policy supplies both
operations through boundary assertions alone.

A local Emacs 31.1 check confirmed that `cat` finds three `cat` substrings in
the rows above, `cat\b` finds only the standalone one, and `\bcat\w*\b`
finds `cats`, `catlike` and `cat`. A separate check in `emacs-lisp-mode` with
`subword-mode` found that `forward-word` stops between `Alpha` and `Beta` in
`AlphaBeta`, where regexp `\b` does not match. Custom word motion therefore
cannot be assumed to share regexp boundary rules. The
[word-motion manual][word-motion] documents the additional motion customization
machinery.

Decision after trial: retain the implemented remainder-inclusive policy for
this version. Word boundaries define the context units; each unit is compared
as a string, and may be a complete word or a fragment at the exact match edge.
For the query `ac`, preceding keys for `callb[ac]k`, `can [ac]cumulate` and
`Char[ac]ter` are `callb`, `can` and `char` with case folding. This mixture
follows the same rule throughout. Excluding the containing word would discard
these fragments, leaving their differences unrepresented and resolving any
remaining ties in source order. Neither choice is claimed as a universal
concordancer convention. N counts context units and additional units refine
ties; word-based ordering can resemble character ordering for partial queries
without violating that definition. Comparison-key highlighting remains
unimplemented. The earlier exclusion probe is historical evidence; production
ERT tests cover inclusion.

### How established is character sorting?

There is evidence beyond the mere existence of a feature:

- [AntConc 3.5.9's official manual][antconc-359], Tool Preferences /
  Concordance, explicitly offers character sorting and gives investigating
  spelling differences as its use. Its reference point is the **first letter**
  of the search term, so its right-side offsets are not automatically the same
  as N characters after the match end. The 4.4.1 manual does not document this
  legacy option; do not assert current-version availability from the 3.x manual.
- The [CQP manual][cqp], sections 2.9 and 3.3, separately demonstrates left
  context sorting by words and by reversed characters. Its example selects
  42 **tokens** and reverses the resulting character key. It is evidence for
  character comparison, not an arbitrary N-character window interface.
- [NINJAL's NPCMJ tutorial][npcmj], slides 16-17, exposes preceding/following
  character-context order alongside corpus order and random order.
- [Shonagon's official instructions][shonagon] allow string ordering of result
  columns, including context. They do not specify a user-selectable N or the
  reversal semantics of the preceding-context column.
- A [Tokyo University of Foreign Studies case-study handbook][tufs-case],
  printed pages 54-55 (PDF pages 58-59), explicitly sorts Himawari's following
  and preceding contexts while investigating `tame` forms in the Taiyo corpus.
  Sorting the following context helps collect irrelevant substring hits for
  manual removal. Printed page 103 gives another context-sorting workflow for
  `ureshii` / `kanashii`. These are concrete research procedures, not usage
  telemetry or a measurement of how often a particular command is invoked.

Assessment: character-based context sorting is established enough to recommend
including it. No command-use statistics were found. The evidence supports the
operation class and practical uses; it does not establish that a configurable
N-character limit is itself a widely used control. A bounded N is occur-kwic's
small, predictable adaptation of those workflows.

Implemented character-key semantics: take up to N
Emacs characters immediately outside the exact match, including whitespace,
punctuation and word fragments. Compare nearest characters first, reversing
only the preceding key. Count buffer characters, not bytes, display columns
or grapheme clusters; never reverse displayed text. Apply the same accessible
line limits, case policy and original-order tie break as for word keys. This
also offers a useful alternative when native word boundaries do not separate
the contexts a user wants to inspect. No word-motion callback or redisplay
measurement is needed for character-key extraction.

## Feasibility checks

[scripts/probe-sort.el](../scripts/probe-sort.el) is a standalone batch probe:

```sh
emacs -Q --batch -l scripts/probe-sort.el
```

On Windows Emacs 31.1, it checks:

- `text-mode` keeps the apostrophe in `don't`; fundamental syntax produces
  `don` and `t`.
- Changing hyphen syntax to a word constituent changes `well-known` from two
  words to one. The experiment modifies a copied syntax table.
- Enabling `subword-mode` splits `AlphaBeta` into `Alpha` and `Beta`, confirming
  use of word-boundary functions as well as syntax tables.
- A three-word after key retains all three components. The synthetic `argue`
  rows compare successive words and retain source order for identical keys.
- Native buffer sorting rearranges two actual result rows while retaining
  their text-property entry identities and canonical entry list. Recomputing
  integer row offsets preserves standard Occur jumps to both source matches;
  the header stays intact.

Set `OCCUR_KWIC_SORT_PROBE_BENCH=1` for optional microbenchmarks. A single
interpreted run over 10,000 repeated 45-character lines measured word-span
extraction at about 45 ms and the existing cumulative-column function at
about 188 ms, over the same 450,000 characters. Sorting 10,000 prebuilt
three-string tuples took about 40 ms, including some garbage collection.

These are separate building blocks. They do not measure complete result-key
extraction, row copying, overlay rebuilding, worst-case custom boundary
functions or end-to-end command latency. They support testing a modest sorting
implementation, not a performance guarantee.

## Implementation path

1. Capture/share immutable word spans per distinct source line in its source
   context. Later sorts can use the snapshot after source edits. Do not apply
   result-mode rules or a changed source to old snapshot text. Changed word
   rules take effect on refresh. Capture is unconditional; the validation
   record measures its collection overhead separately.
2. Build requested keys once per sort and associate rows with source ordinals
   for ties and restoration. Keep the entry/marker ownership list in creation
   order.
3. Use [Emacs's `sort-subr`][sorting] with precomputed keys and a custom
   comparator. Text properties travel with rows. Scan the reordered rows once
   to update integer row/text offsets. This can avoid calling `--populate`,
   which cleans up markers and reinitializes the mode.
4. Drop/rebuild window overlays around reordering and preserve the current
   entry and expanded-row identity. Restore/reset result-local markers such
   as an occurrence arrow: `sort-subr` does not maintain their meaningful
   positions inside moved text.
5. Retain the sort specification for refresh/cloning. Verify multiple windows,
   navigation, cancellation/error handling and narrowed results. Compute keys
   before changing text so extraction failures preserve the view.

Keeping the canonical entry list source-ordered preserves the current prefix
width calculation and reverse-creation marker cleanup. Sorting that list in
place would undermine both assumptions; the probe leaves it untouched.

This path needs no redisplay feedback loop: compute keys, reorder rows and
use the existing layout. The RTL alignment limitation is unchanged.

## Optional external metadata

Separate key extraction from comparison and row reordering. A future provider
can supply enriched keys associated with snapshot/match identifiers, such as
lemmas or user categories. It need not replace the renderer or mutate source
text, and should not run during comparisons or window updates. Built-in word
keys remain the default; a public adapter protocol and external-process
integration are not required in the first version.

The implemented first scope is before/after N words and N characters,
matched-string order and source-order restoration. Source limits, word fragments,
zero-width matches, sort case controls, status and refresh/cloning have explicit
behavior and regression coverage. A narrowed result buffer must be widened
before sorting. The exploratory probe is not an older-Emacs compatibility test.

[lexicography]: https://www.sketchengine.eu/wp-content/uploads/Corpus_tools_lexicographers_2011.pdf
[antconc]: https://www.laurenceanthony.net/software/antconc/releases/AntConc441/docs/help.pdf
[wuerzburg]: https://www.neuphil.uni-wuerzburg.de/anglistik/academic-divisions/englische-sprachwissenschaft/forschung/schwerpunkte/corpus-linguistics/tutorials/
[sketch-guide]: https://www.sketchengine.eu/guide/concordance-a-tool-to-search-a-corpus/
[cqp]: https://cwb.sourceforge.io/files/CQP_Manual.pdf
[npcmj]: https://www2.ninjal.ac.jp/npcmj/wp-content/uploads/2022/03/03_interface.pdf
[word-motion]: https://www.gnu.org/software/emacs/manual/html_node/elisp/Word-Motion.html
[sorting]: https://www.gnu.org/software/emacs/manual/html_node/elisp/Sorting.html
[sketch-cql]: https://www.sketchengine.eu/documentation/cql-basics/
[wordsmith-search]: https://lexically.net/downloads/version9/HTML/search_word_proc.html
[antconc-359]: https://www.laurenceanthony.net/software/antconc/releases/AntConc359/help.pdf
[shonagon]: https://shonagon.ninjal.ac.jp/
[tufs-case]: https://cblle.tufs.ac.jp/assets/files/publications/handbooks_06/index.pdf
[guide]: ../README.md#context-sorting
[validation]: implementation-checks.md
