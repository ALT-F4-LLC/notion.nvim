local M = {}

M.defaults = {
  notion_token_cmd = nil, -- Command to retrieve token, e.g. {"doppler", "secrets", "get", "--plain", "NOTION_TOKEN"}
  database_id = nil,
  page_size = 10,
  cache_ttl = 300,
  debug = false, -- Set to true to show timing information
  sync_debounce_ms = 1000, -- Minimum time between syncs (ms)
}

M.options = {}

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
      vim.notify('Failed to retrieve token from command: ' ..
        vim.inspect(M.options.notion_token_cmd), vim.log.levels.ERROR)
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

return M
