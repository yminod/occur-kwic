# Literary excerpt fixtures

These small, pinned excerpts complement the constructed edge cases. Tests read
the local files; they never download books. Both files are UTF-8 without a BOM,
with LF line endings and one final newline. Their SHA-256 digests are checked
when loading them. Do not reflow lines, normalize punctuation, or regenerate
expected results from occur-kwic output when updating a fixture.

## Sources and extraction

Retrieved on 2026-10-20:

| File | Source | Exact excerpt and conversion | SHA-256 |
| --- | --- | --- | --- |
| `alice.txt` | Lewis Carroll, *Alice's Adventures in Wonderland*, [Project Gutenberg #11](https://www.gutenberg.org/ebooks/11), [UTF-8 text](https://www.gutenberg.org/cache/epub/11/pg11.txt), edition updated 2025-06-26. Credits: Arthur DiBianca and David Widger. | First six prose paragraphs of Chapter I, from `Alice was beginning` through `cupboards as she fell past it.` Source wrapping, blank lines, curly quotes, and emphasis underscores are retained; CRLF becomes LF. | `c5e7692d6176344c3ffff033a28d26fe4325ec52d4ace929784bd3e9302b45c0` |
| `botchan.txt` | 夏目漱石『坊っちゃん』, [青空文庫・作品752](https://www.aozora.gr.jp/cards/000148/card752.html), [ruby text ZIP](https://www.aozora.gr.jp/cards/000148/files/752_ruby_2438.zip), updated 2011-05-20. 入力：真先芳秋、校正：柳沢成雄。底本：筑摩書房「ちくま日本文学全集 夏目漱石」。 | First three prose paragraphs of chapter 一, from `　親譲《おやゆず》り` through `袷の片袖も取り返して来た。` Decode `bocchan.txt` as CP932, convert CRLF to LF, and encode as UTF-8. Keep full paragraph lines, indentation, ruby `《…》`, and `｜` exactly as supplied. Exclude the title, explanatory preamble, chapter heading, and bibliographic footer. | `6c3f85455357df7aa308c7acc9b9775adddd0f91705fadf635d60a57e82c9d5c` |

The full Project Gutenberg license accompanying the Alice source is retained
in [gutenberg-license.txt](gutenberg-license.txt), from `START: FULL LICENSE`
to the end of that source file, removing trailing whitespace. The literary text and accompanying notices
are third-party material; the repository's software license does not replace
those notices.

## Expectations

[../occur-kwic-corpus-tests.el](../occur-kwic-corpus-tests.el) contains fixed
match locations and sort orders. Locations are one-based physical line numbers
and zero-based character offsets, not byte offsets or screen columns. A match's
ID is its one-based index in source order, distinguishing multiple occurrences
on the same line. Alice searches `\b[Ss]he\b` (20 matches), and Botchan searches
`から` (12 matches). Separate Alice searches check lowercase case-sensitive,
case-insensitive, and uppercase smart-case queries.

The locations were enumerated from the fixture text independently of KWIC.
Word keys were reviewed using direct `forward-word` / `backward-word` movement
in a fresh `text-mode` source buffer, without loading occur-kwic or using its
cached word spans, key extraction, or comparison functions. The keys below
record that review, nearest word first. Fixed ID orders were calculated from
these tuples with an independent lexicographic comparison; ties use source ID.
Character orders were calculated from literal fixture characters, with only
the preceding key reversed. No test derives its expected order from the
production sorting functions.

### Alice word keys, N=3

Empty keys at IDs 6, 15, and 18 are intentional: those matches end their
physical source lines. `She` at ID 17 differs in case from the other matches.

| ID | Before, nearest first | After, nearest first |
| --- | --- | --- |
| 1 | twice / or / once | had / peeped / into |
| 2 | So | was / considering / in |
| 3 | as / well / as | could / for / the |
| 4 | when / late / be | thought / it / over |
| 5 | that / her / to | ought / to / have |
| 6 | that / mind / her | — |
| 7 | curiosity / with / burning | ran / across / the |
| 8 | world / the / in | was / to / get |
| 9 | before / herself / stopping | found / herself / falling |
| 10 | or / deep / very | fell / very / slowly |
| 11 | for / slowly / very | had |
| 12 | as / time / of | went / down / to |
| 13 | First / next / happen | tried / to / look |
| 14 | what | was / coming / to |
| 15 | then / anything / see | — |
| 16 | there / and / here | saw / maps / and |
| 17 | pegs / upon / hung | took / down / a |
| 18 | as / shelves / the | — |
| 19 | empty / was / it | did / not / like |
| 20 | as / cupboards | fell / past / it |

For example, after-word N=1 ties IDs 1 and 11 on `had`, retaining ID 1 first.
N=3 instead puts the shorter key `("had")` at ID 11 before
`("had" "peeped" "into")` at ID 1. All `as` preceding keys tie at N=1;
N=3 orders them 20, 18, 12, 3. Case-sensitive preceding sorts also move
`First` and `So` ahead of lowercase words.

### Botchan word keys, N=3

These are Emacs word-motion units, including fragments adjoining a match,
not a Japanese morphological analysis. Ruby remains searchable ordinary text
and can contribute units such as `いば`, `はや`, and `め`.

| ID | Before, nearest first | After, nearest first |
| --- | --- | --- |
| 1 | 時 / 小供の / で | 損ばかりしている / 小学校に / 居る |
| 2 | 二階 / 時分学校の / 居る | 飛び / 降りて / 一週間ほど |
| 3 | 二階 / 新築の / 理由でもない | 首を / 出していたら / 同級生の |
| 4 | そこ / っても / いば | 飛び / 降りる / 事は |
| 5 | した / はや / 囃 | である / 小使 / こづかい |
| 6 | 二階ぐらい / をして / め | 飛び / 降りて / 腰を |
| 7 | った / い / 云 | この / 次は / 抜かさずに |
| 8 | 親類のもの | 西洋製の / ナイフを / 貰 |
| 9 | 注文した / 切ってみろと / 指を | 何だ / 指ぐらいこの / 通りだと |
| 10 | 使えぬ / 手が / になって | 無暗に / 手を / 振 |
| 11 | 中 / 袖の / 苦しがって | おれの / 二の / 腕 |
| 12 | 痛かった / 付いた / 食い | 勘太郎を / 垣根へ / 押しつけておいて |

After-word N=1 ties IDs 2, 4, and 6 on `飛び`; N=3 refines them to 2, 6, 4.
Before-word N=1 ties IDs 2 and 3 on `二階`; N=3 instead puts ID 3 first.
These changes distinguish a word tuple from sorting concatenated context.

## What runs

The normal `scripts/test.sh` and `scripts/test.ps1` entry points include all
six corpus tests. They check exact matches, complete stored rows, source
markers and standard Occur jumps, all six sort methods, N=1 and N=3 for
context sorts, both sort case policies, repeated sorting, and exact source
order restoration after switching sorts. Refresh/clone tests insert a newline
before the source, check the shifted navigation targets, refresh the sorted
original, and verify that an independently sorted snapshot retains its saved
text and survives closing the original.

These are batch data and navigation regressions. They do not measure GUI
pixels or establish whole-book performance or compatibility across Emacs
versions; those remain separate checks.
