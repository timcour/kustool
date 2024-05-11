TEST_DIR=test

.PHONY: test
test:
	@bats $(TEST_DIR)/*.bats
