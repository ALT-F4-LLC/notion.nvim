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
    decode = function(json_string)
      -- Simple JSON decoder for testing that actually parses basic JSON
      if type(json_string) ~= "string" then
        return { success = true }
      end
      -- Handle image test data
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
      -- Try to parse the JSON string with a simple parser
      local function simple_json_parse(str)
        -- Handle the specific test cases
        local expected_str = '{"results": [{"id": "block1", "has_children": true}, {"id": "block2"}], ' ..
                              '"has_more": true, "next_cursor": "cursor1"}'
        if str == expected_str then
          return {
            results = {
              { id = "block1", has_children = true },
              { id = "block2" }
            },
            has_more = true,
            next_cursor = "cursor1"
          }
        elseif str == '{"results": [{"id": "block3"}]}' then
          return {
            results = {
              { id = "block3" }
            }
          }
        elseif str == '{"results": []}' then
          return {
            results = {}
          }
        elseif str == '{"results": [{"id": "block1"}, {"id": "block2"}]}' then
          return {
            results = {
              { id = "block1" },
              { id = "block2" }
            }
          }
        elseif str == '{"results": [{"id": "block1", "in_trash": true}, {"id": "block2"}]}' then
          return {
            results = {
              { id = "block1", in_trash = true },
              { id = "block2" }
            }
          }
        end
        return nil
      end

      local parsed = simple_json_parse(json_string)
      if parsed then
        return parsed
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