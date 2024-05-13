default: test

TEST_DIR=test

.PHONY: check-env
check-env:
ifndef KUSTOOL_ROOT
	$(error KUSTOOL_ROOT is undefined)
endif

.PHONY: test
test: check-env
	@bats $(TEST_DIR)/*.bats
