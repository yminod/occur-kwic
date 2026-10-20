# eyegrep: the original eye-grep helper

[eyegrep.el](eyegrep.el) is preserved here, unchanged, as the predecessor of
`occur-kwic` and a baseline for the [legacy characterization tests](../test/eyegrep-tests.el).
Current development takes place in [occur-kwic.el](../occur-kwic.el).

I have used this personal Emacs tool since around 2010. It centers
matches according to the window width, making the surrounding context easier
to scan by eye without repeatedly shifting my gaze left and right to locate
each match. After looking for something like a grep tool with aligned matches
and finding no suitable tool, I wrote my own in Emacs Lisp.

I last edited the surviving file in 2025 to tidy its form; that date is not
the tool's origin. Earlier implementations are no longer available. Those
versions were substantially rougher than the surviving one.

During early specification discussions with GPT for the modernization project,
I learned that this display resembles KWIC (Key Word In Context).
I developed the original tool without knowing about KWIC. The redesign aims to
improve the Emacs experience and interoperability with standard tools.

This is historical code with known limitations: see the
[layout audit](../docs/layout-audit.md), including the nonterminating search
for some zero-width matches. Its behavior is retained for comparison,
rather than as requirements for the new implementation.
