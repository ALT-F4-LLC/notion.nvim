local M = {}

-- Cache for article content: { [page_id] = markdown_string }
local preview_cache = {}

-- Debounce timer for preview loading
local preview_timer = nil

-- Currently loading page ID (prevent simultaneous loads)
local loading_page_id = nil

-- Lazy-load telescope modules only when needed
-- This allows the module to be required even if telescope isn't installed
local pickers, finders, conf, actions, action_state, previewers

local function ensure_telescope_loaded()
  if not pickers then
    pickers = require('telescope.pickers')
    finders = require('telescope.finders')
    conf = require('telescope.config').values
    actions = require('telescope.actions')
    action_state = require('telescope.actions.state')
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

-- Custom previewer showing page content with caching and debouncing
local function make_previewer()
  ensure_telescope_loaded()

  return previewers.new_buffer_previewer({
    title = "Page Preview",
    define_preview = function(self, entry, status)
      local page = entry.value
      local bufnr = self.state.bufnr
      local page_id = page.id

      -- Cancel any pending timer
      if preview_timer then
        vim.fn.timer_stop(preview_timer)
        preview_timer = nil
      end

      -- Check cache first (instant display, bypass debounce)
      if preview_cache[page_id] then
        local cached_lines = vim.split(preview_cache[page_id], '\n')
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, cached_lines)
        vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')
        return
      end

      -- Show loading message immediately
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# " .. page.title,
        "",
        "Loading article content..."
      })
      vim.api.nvim_buf_set_option(bufnr, 'filetype', 'markdown')

      -- Debounce: only load after user stops moving for 300ms
      preview_timer = vim.fn.timer_start(300, function()
        preview_timer = nil

        -- Check if another article is currently loading
        if loading_page_id then
          -- Show "waiting" message
          if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
              "# " .. page.title,
              "",
              "Another article is loading...",
              "Please wait a moment."
            })
          end
          return
        end

        -- Mark this page as loading
        loading_page_id = page_id

        -- Fetch article content asynchronously
        vim.schedule(function()
          -- Require api module to access get_all_blocks and blocks_to_markdown
          local api = require('notion.api')

          -- Fetch blocks (this will block, but at least we're debounced)
          local blocks = api.get_all_blocks(page_id)

          -- Clear loading state
          loading_page_id = nil

          if not blocks or #blocks == 0 then
            local no_content = {
              "# " .. page.title,
              "",
              "*No content available*",
              "",
              "URL: " .. page.url,
              "Created: " .. format_time(page.created_time),
              "Last Edited: " .. format_time(page.last_edited_time),
            }
            local no_content_str = table.concat(no_content, '\n')
            preview_cache[page_id] = no_content_str
            if vim.api.nvim_buf_is_valid(bufnr) then
              vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, no_content)
            end
            return
          end

          -- Convert blocks to markdown
          local markdown_lines = api.blocks_to_markdown(blocks)

          -- Add title at top
          table.insert(markdown_lines, 1, "")
          table.insert(markdown_lines, 1, "# " .. page.title)

          -- Cache the content
          local content = table.concat(markdown_lines, '\n')
          preview_cache[page_id] = content

          -- Update buffer (check if still valid)
          if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, markdown_lines)
          end
        end)
      end)
    end,
  })
end

-- Main Telescope picker for Notion pages
function M.notion_pages(pages, on_select)
  ensure_telescope_loaded()

  -- Use horizontal layout with preview on the right
  local opts = {
    layout_strategy = "horizontal",
    layout_config = {
      width = 0.95,          -- 95% of screen width
      height = 0.90,         -- 90% of screen height
      preview_width = 0.55,  -- Preview takes 55% of width (balance between list and preview)
      prompt_position = "top",
    }
  }

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

-- Clear preview cache (useful for forcing refresh)
function M.clear_preview_cache()
  preview_cache = {}

  -- Cancel any pending timer
  if preview_timer then
    vim.fn.timer_stop(preview_timer)
    preview_timer = nil
  end

  loading_page_id = nil
end

return M
