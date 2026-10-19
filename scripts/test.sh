#!/bin/sh
# Author: Minoru Yasui
# Assisted-by: Codex:GPT-6.1
# Usage: [EMACS=/path/to/emacs] ./scripts/test.sh [--test-only]
set -eu

script_dir=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
exec "${EMACS:-emacs}" -Q --batch -l "$script_dir/run-tests.el" "$@"
