# Makefile for notion.nvim

.PHONY: test test-watch clean

# Default target
all: test

# Run tests
test:
	@echo "Running tests..."
	@busted --helper=tests/spec_helper.lua

# Run tests with coverage
test-coverage:
	@echo "Running tests with coverage..."
	@busted --helper=tests/spec_helper.lua --coverage
	@luacov

# Watch tests (requires entr)
test-watch:
	@echo "Watching for changes and running tests..."
	@find . -name "*.lua" | entr -c make test

# Lint Lua files
lint:
	@echo "Linting Lua files..."
	@luacheck lua/ tests/ --globals vim

# Clean coverage files
clean:
	@echo "Cleaning coverage files..."
	@rm -f luacov.*.out
	@rm -f luacov.report.out

# Help target
help:
	@echo "Available targets:"
	@echo "  all          - Run tests (default)"
	@echo "  test         - Run tests"
	@echo "  test-coverage- Run tests with coverage report"
	@echo "  test-watch   - Watch files and run tests on changes"
	@echo "  lint         - Lint Lua files"
	@echo "  clean        - Clean coverage files"
	@echo "  help         - Show this help message"