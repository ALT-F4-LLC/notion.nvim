-- Luacheck configuration for notion.nvim

-- Global variables that are OK to use
globals = {
  "vim"
}

-- Ignore specific warnings
ignore = {
  "212", -- Unused argument
  "213", -- Unused loop variable
}

-- File-specific configurations
files = {
  ["tests/*"] = {
    globals = {
      "describe", "it", "before_each", "after_each",
      "assert", "spy", "stub", "mock"
    }
  }
}

-- Lua version
std = "lua54"
