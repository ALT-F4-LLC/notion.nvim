# Agent Guidelines for notion.nvim

## Build/Test Commands
- `make test` - Run all tests with busted
- `make lint` - Lint Lua files with luacheck
- `make test-coverage` - Run tests with coverage report
- `busted tests/api_spec.lua` - Run single test file
- `busted --helper=tests/spec_helper.lua --pattern=specific_test` - Run specific test

## Code Style
- Use 2-space indentation, no tabs
- Snake_case for functions and variables, PascalCase for modules
- Local variables first, then functions
- Use `local M = {}` pattern for modules, return M at end
- Imports at top: `local config = require('notion.config')`
- Error handling: Check return values, use vim.notify for user messages
- Comments: Use `--` for single line, `--[[]]` for blocks
- Global vim namespace: Access via `vim.api`, `vim.fn`, `vim.notify`
- Test globals: `describe`, `it`, `assert` (defined in .luacheckrc)

## Security
- Never hardcode tokens - use environment variables or commands only
- Validate all user inputs before API calls
- Use vim.trim() on external command outputs