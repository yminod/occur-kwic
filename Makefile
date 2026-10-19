EMACS ?= emacs

.PHONY: check test
check:
	"$(EMACS)" -Q --batch -l scripts/check.el
	$(MAKE) test EMACS="$(EMACS)"

test:
	"$(EMACS)" -Q --batch -L . -l test/eyegrep-tests.el -l test/occur-kwic-tests.el -f ert-run-tests-batch-and-exit
