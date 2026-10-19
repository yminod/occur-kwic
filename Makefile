EMACS ?= emacs

.PHONY: check test
check:
	EMACS="$(EMACS)" ./scripts/test.sh

test:
	EMACS="$(EMACS)" ./scripts/test.sh --test-only
