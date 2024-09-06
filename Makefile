default: test

TEST_DIR=test

KUSTOOL_ROOT ?= $(shell pwd)

.PHONY: test
test:
	KUSTOOL_ROOT="${KUSTOOL_ROOT}" bats $(TEST_DIR)/*.bats

.PHONY: test-only
test-only:
	KUSTOOL_ROOT="${KUSTOOL_ROOT}" bats $(TEST_DIR)/*.bats --filter-tags only
