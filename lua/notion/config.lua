local M = {}

M.defaults = {
  notion_token_cmd = nil, -- Command to retrieve token, e.g. {"doppler", "secrets", "get", "--plain", "NOTION_TOKEN"}
  database_id = nil,
  page_size = 10,
  cache_ttl = 300,
  debug = false, -- Set to true to show timing information
  sync_debounce_ms = 1000, -- Minimum time between syncs (ms)
  use_telescope = nil, -- nil = auto-detect, true = force telescope, false = force vim.ui.select
}

M.options = {}

-- Sanitize command for display (remove sensitive parts)
local function sanitize_command_for_display(cmd)
  if type(cmd) == "table" then
    local sanitized = {}
    for i, part in ipairs(cmd) do
      -- Keep command name and safe flags, redact potential token values
      if i == 1 then
        -- Always keep the command name
        table.insert(sanitized, part)
      elseif part:match("^%-%-?[%w%-]+$") then
        -- Keep flags that start with - or --
        table.insert(sanitized, part)
      else
        -- Redact everything else (likely token values, secrets, etc.)
        table.insert(sanitized, '[REDACTED]')
      end
    end
    return sanitized
  elseif type(cmd) == "string" then
    -- For string commands, only show the first word (command name)
    local command_name = cmd:match("^%S+")
    return command_name and (command_name .. " [REDACTED]") or "[REDACTED]"
  end
  return "[REDACTED]"
end

-- Helper function to execute a command and get the output
local function execute_command(cmd)
  if type(cmd) == "table" then
    -- Handle array of command parts
    local result = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      return nil
    end
    return vim.trim(result)
  elseif type(cmd) == "string" then
    -- Handle single string command
    local result = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      return nil
    end
    return vim.trim(result)
  end
  return nil
end

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.defaults, opts or {})

  -- Security: Only allow token from environment variable or command - never hardcoded
  if M.options.notion_token_cmd then
    -- Try command-based retrieval first
    M.options.notion_token = execute_command(M.options.notion_token_cmd)
    if not M.options.notion_token then
      local sanitized_cmd = sanitize_command_for_display(M.options.notion_token_cmd)
      vim.notify('Failed to retrieve token from command: ' ..
        vim.inspect(sanitized_cmd), vim.log.levels.ERROR)
    end
  else
    -- Fall back to environment variable
    M.options.notion_token = vim.env.NOTION_TOKEN
  end

  if not M.options.database_id then
    M.options.database_id = vim.env.NOTION_DATABASE_ID
  end

  if not M.options.notion_token then
    vim.notify('Notion token not configured. Set NOTION_TOKEN environment variable or ' ..
      'configure notion_token_cmd', vim.log.levels.WARN)
  end
end

function M.get(key)
  return M.options[key]
end

function M.get_last_sync(page_id)
  return M.options['last_sync_' .. page_id]
end

function M.set_last_sync(page_id, timestamp)
  M.options['last_sync_' .. page_id] = timestamp
end

function M.telescope_available()
  local ok = pcall(require, 'telescope')
  return ok
end

function M.should_use_telescope()
  local use_telescope = M.options.use_telescope
  if use_telescope == nil then
    return M.telescope_available()  -- Auto-detect
  end
  return use_telescope
end

return M
