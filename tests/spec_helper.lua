-- Test helper to set up Neovim-like environment for testing

-- Add lua directory to package path
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

-- Mock vim global
_G.vim = {
  log = {
    levels = {
      DEBUG = 0,
      INFO = 1,
      WARN = 2,
      ERROR = 3
    }
  },

  api = {
    nvim_create_user_command = function() end,
    nvim_create_buf = function() return 1 end,
    nvim_buf_set_name = function() end,
    nvim_buf_set_lines = function() end,
    nvim_buf_set_option = function() end,
    nvim_buf_set_var = function() end,
    nvim_buf_get_var = function() return nil end,
    nvim_get_current_buf = function() return 1 end,
    nvim_set_current_buf = function() end,
    nvim_list_bufs = function() return {} end,
    nvim_buf_delete = function() end,
    nvim_create_autocmd = function() end
  },

  fn = {
    system = function() return "" end,
    has = function() return 0 end
  },

  v = {
    shell_error = 0
  },

  env = {},

  g = {},

  notify = function() end,

  json = {
    encode = function(data)
      -- Simple JSON encoder for testing
      if type(data) == "table" then
        return "{}"
      else
        return tostring(data)
      end
    end,
    decode = function(json)
      -- Simple JSON decoder for testing
      return { success = true }
    end
  },

  tbl_deep_extend = function(behavior, ...)
    local result = {}
    for i = 1, select('#', ...) do
      local tbl = select(i, ...)
      if tbl then
        for k, v in pairs(tbl) do
          result[k] = v
        end
      end
    end
    return result
  end,

  tbl_filter = function(func, t)
    local result = {}
    for _, v in ipairs(t) do
      if func(v) then
        table.insert(result, v)
      end
    end
    return result
  end,

  trim = function(s)
    return s:match("^%s*(.-)%s*$")
  end,

  ui = {
    select = function(items, opts, on_choice)
      -- Mock select - just call with first item
      if #items > 0 then
        on_choice(items[1])
      end
    end
  },

  loop = {
    hrtime = function()
      return os.clock() * 1000000000 -- nanoseconds
    end
  },

  inspect = function(obj)
    -- Simple inspector for testing
    if type(obj) == "table" then
      return vim.json.encode(obj)
    else
      return tostring(obj)
    end
  end
}

-- Helper function to reset mocks between tests
local function reset_vim_mocks()
  vim.g = {}
  vim.env = {}
  vim.v.shell_error = 0
end

-- Export the helper function to the global scope
_G.reset_vim_mocks = reset_vim_mocks