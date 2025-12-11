local M = {}

-- Lazy-load telescope modules only when needed
-- This allows the module to be required even if telescope isn't installed
local pickers, finders, conf, actions, action_state, previewers

local function ensure_telescope_loaded()
  if not pickers then
    pickers = require('telescope.pickers')
    finders = require('telescope.finders')
    conf = require('telescope.config').values
    actions = require('telescope.actions')
    action_state = require('telescope.action_state')
    previewers = require('telescope.previewers')
  end
end

-- Format ISO 8601 timestamp to readable format
local function format_time(iso_string)
  if not iso_string then return "Unknown" end
  local date = iso_string:match("(%d%d%d%d%-%d%d%-%d%d)")
  local time = iso_string:match("T(%d%d:%d%d)")
  return date and time and (date .. " " .. time) or iso_string
end

-- Custom entry maker for Notion pages
local function make_entry_maker()
  return function(page)
    return {
      value = page,
      display = function(entry)
        local last_edited = format_time(entry.value.last_edited_time):match("(%d%d%d%d%-%d%d%-%d%d)")
        return string.format("%s  [%s]", entry.value.title, last_edited or "Unknown")
      end,
      ordinal = page.title,
    }
  end
end

-- Custom previewer showing page metadata
local function make_previewer()
  ensure_telescope_loaded()

  return previewers.new_buffer_previewer({
    title = "Page Details",
    define_preview = function(self, entry, status)
      local page = entry.value
      local lines = {
        "Title: " .. page.title,
        "",
        "URL: " .. page.url,
        "",
        "Created: " .. format_time(page.created_time),
        "Last Edited: " .. format_time(page.last_edited_time),
        "",
        "Page ID: " .. page.id,
      }
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', 'markdown')
    end,
  })
end

-- Main Telescope picker for Notion pages
function M.notion_pages(pages, on_select)
  ensure_telescope_loaded()

  local opts = {}

  pickers.new(opts, {
    prompt_title = "Notion Pages",
    finder = finders.new_table({
      results = pages,
      entry_maker = make_entry_maker(),
    }),
    sorter = conf.generic_sorter(opts),
    previewer = make_previewer(),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          on_select(selection.value)
        end
      end)
      return true
    end,
  }):find()
end

return M
