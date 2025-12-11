-- Test helper to set up Neovim-like environment for testing

-- Add lua directory to package path
package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"

-- Store original pcall
local original_pcall = pcall

-- Override pcall to handle telescope require
_G.pcall = function(fn, ...)
  -- Only intercept pcall(require, 'something') calls
  if fn == require then
    local args = {...}
    local module_name = args[1]

    -- Check if this is pcall(require, 'telescope')
    if module_name == 'telescope' then
      if _G.vim and _G.vim.telescope and _G.vim.telescope.available then
        return true, {}
      else
        return false, "module 'telescope' not found"
      end
    end

    -- Check if this is pcall(require, 'notion.telescope')
    if module_name == 'notion.telescope' then
      if _G.vim and _G.vim.telescope and _G.vim.telescope.available then
        -- Return a mock telescope picker module
        return true, {
          notion_pages = function(pages, on_select)
            -- Mock implementation - just select first page
            if #pages > 0 then
              on_select(pages[1])
            end
          end
        }
      else
        return false, "module 'notion.telescope' not found"
      end
    end
  end

  -- Default behavior for all other cases
  return original_pcall(fn, ...)
end

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
      -- Simple JSON encoder for testing that actually works
      local function encode_value(val)
        local val_type = type(val)
        if val_type == "string" then
          return '"' .. val:gsub('"', '\\"') .. '"'
        elseif val_type == "number" then
          return tostring(val)
        elseif val_type == "boolean" then
          return tostring(val)
        elseif val_type == "nil" then
          return "null"
        elseif val_type == "table" then
          -- Check if it's an array (all keys are sequential numbers starting from 1)
          local is_array = true
          local max_index = 0
          for k, _ in pairs(val) do
            if type(k) ~= "number" or k < 1 or k ~= math.floor(k) then
              is_array = false
              break
            end
            max_index = math.max(max_index, k)
          end

          if is_array and max_index == #val then
            -- Encode as array
            local parts = {}
            for i = 1, #val do
              table.insert(parts, encode_value(val[i]))
            end
            return "[" .. table.concat(parts, ", ") .. "]"
          else
            -- Encode as object
            local parts = {}
            for k, v in pairs(val) do
              local key = type(k) == "string" and k or tostring(k)
              table.insert(parts, '"' .. key .. '": ' .. encode_value(v))
            end
            return "{" .. table.concat(parts, ", ") .. "}"
          end
        else
          return "null"
        end
      end
      return encode_value(data)
    end,
    decode = function(json_string)
      -- Simple JSON decoder for testing that actually parses JSON
      if type(json_string) ~= "string" then
        return { success = true }
      end

      -- Handle legacy pattern-based test data (for backward compatibility)
      if json_string:match('page%-with%-properties%-Test Page') then
        return {
          properties = {
            Name = {
              title = { { text = { content = "Test Page" } } }
            }
          },
          url = "https://notion.so/test-page"
        }
      elseif json_string:match('blocks%-with%-images') then
        return {
          results = {
            {
              id = "img1",
              type = "image",
              image = {
                type = "external",
                external = { url = "https://example.com/image.jpg" },
                caption = { { text = { content = "Test Caption" } } }
              }
            },
            {
              id = "img2",
              type = "image",
              image = {
                type = "file",
                file = { url = "https://files.notion.com/image.png" },
                caption = {}
              }
            },
            {
              id = "para1",
              type = "paragraph",
              paragraph = {
                rich_text = { { text = { content = "Regular text" } } }
              }
            }
          }
        }
      elseif json_string:match('sync%-heading') then
        return {
          results = {
            {
              id = "existing1",
              type = "heading_1",
              heading_1 = {
                rich_text = { { text = { content = "Test Page" } } }
              }
            }
          }
        }
      elseif json_string:match('complex%-caption') then
        return {
          results = {
            {
              id = "img1",
              type = "image",
              image = {
                type = "external",
                external = { url = "https://example.com/test.jpg" },
                caption = {
                  { text = { content = "Image with " }, annotations = { bold = true } },
                  { text = { content = "formatted" }, annotations = { italic = true } },
                  { text = { content = " caption" } }
                }
              }
            }
          }
        }
      end

      -- Try to use a real JSON parser if available (dkjson or cjson)
      local has_dkjson, dkjson = pcall(require, "dkjson")
      if has_dkjson then
        local obj = dkjson.decode(json_string, 1, nil)
        if obj then
          return obj
        end
      end

      -- Fallback: try to load the string as Lua code (UNSAFE in production, but OK for tests)
      -- Convert JSON to Lua table syntax
      local lua_str = json_string
        :gsub("%[", "{")
        :gsub("%]", "}")
        :gsub("null", "nil")
        :gsub('"([^"]+)":%s*', '["%1"] = ')
        :gsub('true', 'true')
        :gsub('false', 'false')

      local fn = load("return " .. lua_str)
      if fn then
        local ok, result = pcall(fn)
        if ok then
          return result
        end
      end

      -- Default fallback
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

  telescope = {
    available = false,  -- Override in individual tests
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