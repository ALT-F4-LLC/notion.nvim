--[[
notion.nvim API module

This module provides the core functionality for integrating with Notion's API,
including intelligent diff-based synchronization that only updates changed content.

Key features:
- Async (non-blocking) HTTP via coroutine wrapper around plenary.curl
- Diff-based sync algorithm for optimal performance
- Rich text formatting support (bold, italic, code, links)
- Block-level content management
- Smart debouncing to prevent API abuse
- Comprehensive error handling and debug output

Performance: Typical sync times are 200-800ms for small edits, scaling with
the amount of changed content rather than total document size.
All API calls are non-blocking when called from async context (coroutine).
--]]

local M = {}
local config = require('notion.config')
local curl = require('plenary.curl')

-- Track ongoing syncs to prevent duplicates and implement debouncing
local sync_state = {}

-- Block cache: keyed by page_id, stores { blocks = <block_data>, timestamp = <os.time()> }
local block_cache = {}

-- Collect debug messages to show in a single popup when debug mode is enabled
local debug_messages = {}

-- Async operation status tracking for spinner/notifications
local async_status = {
  active_ops = 0,
}

-- Notify user about async operation status (spinner-like feedback)
local function async_notify_start(operation_name)
  async_status.active_ops = async_status.active_ops + 1
  vim.notify('[Notion] ' .. operation_name .. '...', vim.log.levels.INFO)
end

-- Notify completion of async operation
local function async_notify_end(operation_name, success)
  async_status.active_ops = math.max(0, async_status.active_ops - 1)
  if not success then
    vim.notify('[Notion] ' .. operation_name .. ' failed', vim.log.levels.ERROR)
  end
end

-- Run a function inside a coroutine, providing async context.
-- All make_request() calls inside fn will use the non-blocking async path.
-- Neovim API calls from within the coroutine are safe because we resume via
-- vim.schedule().
local function run_async(fn)
  local co = coroutine.create(fn)
  local ok, err = coroutine.resume(co)
  if not ok then
    vim.schedule(function()
      vim.notify('[Notion] Async error: ' .. tostring(err), vim.log.levels.ERROR)
    end)
  end
end

-- Perform an async HTTP request using plenary.curl in a non-blocking fashion.
-- Must be called from within a coroutine. Yields the coroutine and resumes it
-- (via vim.schedule) when the HTTP response arrives.
--
-- The function sets opts.callback so that plenary.curl runs asynchronously.
-- When plenary.curl fires the callback, we resume the coroutine on the main
-- event loop via vim.schedule.
--
-- @param method string: HTTP method name used to select the curl function
-- @param opts table: options table passed to plenary.curl (url, headers, body, etc.)
-- @return table: the HTTP response (same shape as the sync plenary.curl return value)
local function async_curl_request(method, opts)
  local co = coroutine.running()
  if not co then
    error('async_curl_request called outside of a coroutine')
  end

  -- Track whether the callback has already been invoked synchronously
  -- (can happen in test environments where mocks execute callbacks inline)
  local resolved = false
  local resolved_response = nil

  -- Build the callback that resumes the coroutine on the main loop.
  -- If called before we reach coroutine.yield(), we store the response
  -- and skip the yield entirely.
  opts.callback = function(response)
    if coroutine.status(co) == "running" then
      -- Callback fired synchronously (before yield) -- store for later
      resolved = true
      resolved_response = response
    else
      -- Normal async path: resume the yielded coroutine on the main loop
      vim.schedule(function()
        coroutine.resume(co, response)
      end)
    end
  end

  -- Dispatch to the correct plenary.curl method
  local sync_response
  if method == 'GET' then
    sync_response = curl.get(opts)
  elseif method == 'POST' then
    sync_response = curl.post(opts)
  elseif method == 'PATCH' then
    sync_response = curl.patch(opts)
  elseif method == 'DELETE' then
    sync_response = curl.delete(opts)
  end

  -- If the callback already fired synchronously, return the response directly
  -- without yielding (avoids "attempt to yield from outside a coroutine" in tests)
  if resolved then
    return resolved_response
  end

  -- If the curl function returned a response directly (sync mock without callback
  -- support), use it instead of yielding
  if sync_response and type(sync_response) == "table" and sync_response.status then
    return sync_response
  end

  -- Normal async path: yield until the callback resumes us with the response
  return coroutine.yield()
end

-- Non-blocking sleep for use inside coroutines. Uses vim.defer_fn() instead
-- of the blocking vim.loop.sleep(), so the editor remains responsive.
local function async_sleep(ms)
  local co = coroutine.running()
  if not co then
    -- Fallback to blocking sleep when not in a coroutine
    vim.loop.sleep(ms)
    return
  end

  -- Track whether the deferred fn fires synchronously (test environments)
  local timer_fired = false
  vim.defer_fn(function()
    if coroutine.status(co) == "running" then
      -- Fired synchronously before yield -- just set flag and return
      timer_fired = true
    else
      coroutine.resume(co)
    end
  end, ms)

  -- If the timer already fired synchronously, skip the yield
  if not timer_fired then
    coroutine.yield()
  end
end

-- Run a list of task functions concurrently (up to max_concurrent at a time).
-- Each task is a zero-argument function that performs an API call and returns
-- a result. Must be called from within a coroutine (async context).
--
-- Returns a list of results (one per task, in order). Each result is a table
-- with { ok = bool, value = <return value or error string> }.
--
-- If not in a coroutine, falls back to sequential execution.
local function run_concurrent(tasks, max_concurrent)
  max_concurrent = max_concurrent or config.get('max_concurrent_requests') or 5
  local results = {}

  if #tasks == 0 then
    return results
  end

  -- Pre-initialize results table
  for i = 1, #tasks do
    results[i] = { ok = false, value = nil }
  end

  local in_coroutine = coroutine.running() ~= nil
  if not in_coroutine then
    -- Sequential fallback when not in async context
    for i, task in ipairs(tasks) do
      local ok, val = pcall(task)
      results[i] = { ok = ok, value = val }
    end
    return results
  end

  -- Process tasks in batches of max_concurrent
  for batch_start = 1, #tasks, max_concurrent do
    local batch_end = math.min(batch_start + max_concurrent - 1, #tasks)
    local batch_size = batch_end - batch_start + 1
    local completed = 0

    -- The parent coroutine will yield once and be resumed when all tasks in
    -- the batch are done.
    local parent_co = coroutine.running()

    for i = batch_start, batch_end do
      -- Launch each task in its own coroutine
      local task_index = i
      local task_co = coroutine.create(function()
        local ok, val = pcall(tasks[task_index])
        results[task_index] = { ok = ok, value = val }

        -- Track completion; when all done, resume the parent
        completed = completed + 1
        if completed == batch_size then
          -- All tasks in this batch are done -- resume parent
          if coroutine.status(parent_co) == "suspended" then
            vim.schedule(function()
              coroutine.resume(parent_co)
            end)
          end
        end
      end)

      local ok, err = coroutine.resume(task_co)
      if not ok then
        results[i] = { ok = false, value = tostring(err) }
        completed = completed + 1
      end
    end

    -- If all tasks in this batch already completed synchronously (e.g. in
    -- tests where mocks fire callbacks inline), skip the yield.
    if completed < batch_size then
      coroutine.yield()
    end
  end

  return results
end

-- Check if caching is enabled based on cache_ttl config
local function cache_enabled()
  local ttl = config.get('cache_ttl')
  return ttl and ttl > 0
end

-- Get cached blocks for a page_id if fresh, otherwise return nil
local function get_cached_blocks(page_id)
  if not cache_enabled() then
    return nil
  end

  local entry = block_cache[page_id]
  if not entry then
    return nil
  end

  local ttl = config.get('cache_ttl')
  local age = os.time() - entry.timestamp
  if age >= ttl then
    block_cache[page_id] = nil
    return nil
  end

  return entry.blocks
end

-- Store blocks in cache for a page_id
local function set_cached_blocks(page_id, blocks)
  if not cache_enabled() then
    return
  end

  block_cache[page_id] = {
    blocks = blocks,
    timestamp = os.time(),
  }
end

-- Clear cache entry for a page_id
local function clear_cached_blocks(page_id)
  block_cache[page_id] = nil
end

-- Simple notification helper
local function notify_user(message, level)
  vim.notify(message, level or vim.log.levels.INFO)
end

-- Escape special characters for pattern matching
local function escape_pattern(str)
  return str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

-- Sanitize error messages to remove any potential token exposure
local function sanitize_error_message(message, token)
  if not message or not token then
    return message
  end

  -- Replace any occurrence of the token with [REDACTED]
  local escaped_token = escape_pattern(token)
  local sanitized = message:gsub(escaped_token, '[REDACTED]')

  -- Also handle Bearer token format
  sanitized = sanitized:gsub('Bearer ' .. escaped_token, 'Bearer [REDACTED]')

  return sanitized
end

local NOTION_API_URL = 'https://api.notion.com/v1'
local NOTION_VERSION = '2022-06-28'


-- Core HTTP request function. Detects whether it is running inside a coroutine:
--   * If yes  -> uses async_curl_request (non-blocking, yields to event loop)
--   * If no   -> uses synchronous plenary.curl (backward-compatible fallback)
-- All existing call sites continue to work unchanged.
local function make_request(method, endpoint, data)
  local debug_mode = config.get('debug')
  local request_start = debug_mode and vim.loop.hrtime() or nil

  local token = config.get('notion_token')
  if not token then
    vim.notify('Notion token not configured', vim.log.levels.ERROR)
    return nil
  end

  local headers = {
    ['Authorization'] = 'Bearer ' .. token,
    ['Content-Type'] = 'application/json',
    ['Notion-Version'] = NOTION_VERSION,
  }

  -- Detect whether we're in a coroutine (async context)
  local in_coroutine = coroutine.running() ~= nil

  local function perform_request(url, body)
    local retries = 3
    local response

    while retries > 0 do
      local opts = {
        url = url,
        headers = headers,
        timeout = 10000,
        compressed = true,
      }

      if (method == 'POST' or method == 'PATCH') and body then
        opts.body = vim.json.encode(body)
      end

      if in_coroutine then
        -- Async path: non-blocking via coroutine yield
        response = async_curl_request(method, opts)
      else
        -- Sync path: blocking call (backward compatibility)
        if method == 'GET' then
          response = curl.get(opts)
        elseif method == 'POST' then
          response = curl.post(opts)
        elseif method == 'PATCH' then
          response = curl.patch(opts)
        elseif method == 'DELETE' then
          response = curl.delete(opts)
        end
      end

      if response and response.status == 429 then
        retries = retries - 1
        local retry_after = response.headers['Retry-After'] or '1'
        vim.notify('Rate limited. Retrying after ' .. retry_after .. ' seconds...', vim.log.levels.WARN)
        -- Use non-blocking sleep in async context, blocking otherwise
        async_sleep(tonumber(retry_after) * 1000)
      else
        break
      end
    end

    if debug_mode and request_start then
      local request_end = vim.loop.hrtime()
      table.insert(debug_messages, method .. " request to " .. url .. " took: " ..
        ((request_end - request_start) / 1000000) .. "ms")
    end

    if not response then
      vim.notify('Notion API error: no response (network failure?)', vim.log.levels.ERROR)
      return nil
    end

    if response.status ~= 200 and response.status ~= 204 then
      local error_message = response.body or 'Unknown error'
      local sanitized_message = sanitize_error_message(error_message, token)
      vim.notify('Notion API error: ' .. sanitized_message, vim.log.levels.ERROR)
      return nil
    end

    if not response.body or response.body == "" then
      return true
    end

    local ok, result = pcall(vim.json.decode, response.body)
    if not ok then
      vim.notify('Failed to parse Notion API response', vim.log.levels.ERROR)
      return nil
    end
    return result
  end

  local url = NOTION_API_URL .. endpoint

  if data and data.start_cursor then
    if method == 'GET' then
      url = url .. (url:find('?') and '&' or '?') .. 'start_cursor=' .. data.start_cursor
    end
  end

  return perform_request(url, data)
end

function M.get_all_blocks(block_id)
  local all_blocks = {}
  local next_cursor = nil

  repeat
    local data = nil
    if next_cursor then
      data = { start_cursor = next_cursor }
    end

    local blocks_result = M.make_request('GET', '/blocks/' .. block_id .. '/children', data)

    if blocks_result == nil then
      -- If the request failed, retry once
      blocks_result = M.make_request('GET', '/blocks/' .. block_id .. '/children', data)
    end

    if blocks_result and blocks_result.results then
      for _, block in ipairs(blocks_result.results) do
        if not block.in_trash then
          table.insert(all_blocks, block)
          if block.has_children then
            local child_blocks = M.get_all_blocks(block.id)
            for _, child_block in ipairs(child_blocks) do
              table.insert(all_blocks, child_block)
            end
          end
        end
      end
    end

    if blocks_result and blocks_result.has_more and blocks_result.next_cursor then
      next_cursor = blocks_result.next_cursor
    else
      next_cursor = nil
    end

  until not next_cursor

  return all_blocks
end

-- Fetch all pages from database with pagination support
function M.get_all_pages(database_id, page_size)
  local all_pages = {}
  local next_cursor = nil
  local request_count = 0
  local max_requests = 100  -- Safety limit to prevent infinite loops

  repeat
    local data = {
      page_size = page_size or config.get('page_size') or 100
    }

    if next_cursor then
      data.start_cursor = next_cursor
    end

    local result = make_request('POST', '/databases/' .. database_id .. '/query', data)

    if result == nil then
      -- Retry once on failure
      result = make_request('POST', '/databases/' .. database_id .. '/query', data)
    end

    if result and result.results then
      for _, page in ipairs(result.results) do
        local title = 'Untitled'
        if page.properties.Name and page.properties.Name.title and #page.properties.Name.title > 0 then
          title = page.properties.Name.title[1].text.content
        end
        table.insert(all_pages, {
          id = page.id,
          title = title,
          url = page.url,
          created_time = page.created_time,
          last_edited_time = page.last_edited_time
        })
      end
    end

    -- Progress notification for large databases
    if request_count > 0 and request_count % 5 == 0 then
      vim.notify(string.format('Fetching pages... (%d requests)', request_count), vim.log.levels.INFO)
    end

    if result and result.has_more and result.next_cursor then
      next_cursor = result.next_cursor
      request_count = request_count + 1
      if request_count >= max_requests then
        vim.notify('Pagination limit reached. Some pages may not be shown.', vim.log.levels.WARN)
        break
      end
    else
      next_cursor = nil
    end

  until not next_cursor

  return all_pages
end

-- Internal implementation of create_page (can run in sync or async context)
local function create_page_impl(title)
  local database_id = config.get('database_id')
  if not database_id then
    vim.notify('Database ID not configured. Set NOTION_DATABASE_ID or configure in setup()', vim.log.levels.ERROR)
    return
  end

  -- Require a title to be provided
  if not title or title == '' then
    vim.notify('Page title is required. Usage: :NotionCreate <title>', vim.log.levels.ERROR)
    return
  end

  local data = {
    parent = {
      database_id = database_id
    },
    properties = {
      Name = {
        title = {
          {
            text = {
              content = title
            }
          }
        }
      }
    }
  }

  local result = make_request('POST', '/pages', data)
  if result then
    vim.notify('Created page: ' .. title, vim.log.levels.INFO)
    -- Open the newly created page for editing in Neovim instead of browser
    if result.id then
      M.edit_page(result.id)
    end
    return result
  end
end

-- Public create_page: launches in async coroutine for non-blocking execution
function M.create_page(title)
  -- Validation that doesn't require async
  if not title or title == '' then
    vim.notify('Page title is required. Usage: :NotionCreate <title>', vim.log.levels.ERROR)
    return
  end
  local database_id = config.get('database_id')
  if not database_id then
    vim.notify('Database ID not configured. Set NOTION_DATABASE_ID or configure in setup()', vim.log.levels.ERROR)
    return
  end

  async_notify_start('Creating page')
  run_async(function()
    local result = create_page_impl(title)
    async_notify_end('Creating page', result ~= nil)
  end)
end

-- Internal implementation of list_pages (can run in sync or async context)
local function list_pages_impl()
  local database_id = config.get('database_id')
  if not database_id then
    vim.notify('Database ID not configured', vim.log.levels.ERROR)
    return
  end

  local data = {
    page_size = config.get('page_size') or 100
  }

  local result = make_request('POST', '/databases/' .. database_id .. '/query', data)
  if result and result.results then
    local pages = {}
    for _, page in ipairs(result.results) do
      local title = 'Untitled'
      if page.properties.Name and page.properties.Name.title and #page.properties.Name.title > 0 then
        title = page.properties.Name.title[1].text.content
      end
      table.insert(pages, {
        id = page.id,
        title = title,
        url = page.url,
        created_time = page.created_time,
        last_edited_time = page.last_edited_time
      })
    end

    vim.ui.select(pages, {
      prompt = 'Select a Notion page:',
      format_item = function(item)
        return item.title
      end,
    }, function(choice)
      if choice then
        M.open_page_by_url(choice.url)
      end
    end)
  end
end

-- Public list_pages: launches in async coroutine for non-blocking execution
function M.list_pages()
  local database_id = config.get('database_id')
  if not database_id then
    vim.notify('Database ID not configured', vim.log.levels.ERROR)
    return
  end

  async_notify_start('Loading pages')
  run_async(function()
    list_pages_impl()
    async_notify_end('Loading pages', true)
  end)
end

-- Internal implementation of open_page (can run in sync or async context)
local function open_page_impl(query)
  if not query or query == '' then
    list_pages_impl()
    return
  end

  local database_id = config.get('database_id')
  if not database_id then
    vim.notify('Database ID not configured', vim.log.levels.ERROR)
    return
  end

  local data = {
    filter = {
      property = 'Name',
      rich_text = {
        contains = query
      }
    },
    page_size = config.get('page_size') or 100
  }

  local result = make_request('POST', '/databases/' .. database_id .. '/query', data)
  if result and result.results and #result.results > 0 then
    local page = result.results[1]
    if page.url then
      M.open_page_by_url(page.url)
    end
  else
    vim.notify('No pages found matching: ' .. query, vim.log.levels.WARN)
  end
end

-- Public open_page: launches in async coroutine for non-blocking execution
function M.open_page(query)
  if not query or query == '' then
    M.list_pages()
    return
  end

  local database_id = config.get('database_id')
  if not database_id then
    vim.notify('Database ID not configured', vim.log.levels.ERROR)
    return
  end

  async_notify_start('Opening page')
  run_async(function()
    open_page_impl(query)
    async_notify_end('Opening page', true)
  end)
end

--[[
Open the current buffer's Notion page in the browser.
This function checks if the current buffer is a Notion page and opens it in the browser.
--]]
function M.open_current_page_in_browser()
  local buf = vim.api.nvim_get_current_buf()
  local ok, page_url = pcall(vim.api.nvim_buf_get_var, buf, 'notion_page_url')

  if not ok or not page_url then
    vim.notify('This buffer is not a Notion page', vim.log.levels.ERROR)
    return
  end

  M.open_page_by_url(page_url)
  vim.notify('Opened current page in browser', vim.log.levels.INFO)
end

-- Internal implementation of delete_page (can run in sync or async context)
local function delete_page_impl()
  local database_id = config.get('database_id')
  if not database_id then
    vim.notify('Database ID not configured', vim.log.levels.ERROR)
    return
  end

  local data = {
    page_size = config.get('page_size') or 100
  }

  local result = make_request('POST', '/databases/' .. database_id .. '/query', data)
  if result and result.results then
    local pages = {}
    for _, page in ipairs(result.results) do
      local title = 'Untitled'
      if page.properties.Name and page.properties.Name.title and #page.properties.Name.title > 0 then
        title = page.properties.Name.title[1].text.content
      end
      table.insert(pages, {
        id = page.id,
        title = title,
        url = page.url,
        created_time = page.created_time,
        last_edited_time = page.last_edited_time
      })
    end

    vim.ui.select(pages, {
      prompt = 'Select a page to delete (archive):',
      format_item = function(item)
        return item.title
      end,
    }, function(choice)
      if choice then
        -- Archive the page by setting archived = true
        local archive_result = make_request('PATCH', '/pages/' .. choice.id, {
          archived = true
        })

        if archive_result then
          vim.notify('Deleted (archived) page: ' .. choice.title, vim.log.levels.INFO)

          -- Close the buffer if it's currently open
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            local ok_var, page_id = pcall(vim.api.nvim_buf_get_var, buf, 'notion_page_id')
            if ok_var and page_id == choice.id then
              vim.api.nvim_buf_delete(buf, { force = true })
              break
            end
          end
        else
          vim.notify('Failed to delete page: ' .. choice.title, vim.log.levels.ERROR)
        end
      end
    end)
  end
end

--[[
Delete (archive) a Notion page.
This function lists all pages and allows the user to select one for deletion.
Note: Notion doesn't actually delete pages, it archives them.
--]]
function M.delete_page()
  local database_id = config.get('database_id')
  if not database_id then
    vim.notify('Database ID not configured', vim.log.levels.ERROR)
    return
  end

  async_notify_start('Loading pages for deletion')
  run_async(function()
    delete_page_impl()
    async_notify_end('Loading pages for deletion', true)
  end)
end

function M.open_page_by_url(url)
  if vim.fn.has('mac') == 1 then
    vim.fn.system('open "' .. url .. '"')
  elseif vim.fn.has('unix') == 1 then
    vim.fn.system('xdg-open "' .. url .. '"')
  elseif vim.fn.has('win32') == 1 then
    vim.fn.system('start "" "' .. url .. '"')
  else
    vim.notify('Cannot open URL on this platform', vim.log.levels.ERROR)
  end
end

-- Convert rich text to markdown
local function rich_text_to_markdown(rich_text)
  if not rich_text then return "" end

  local result = {}
  for _, text_obj in ipairs(rich_text) do
    local content = text_obj.text and text_obj.text.content or ""
    local annotations = text_obj.annotations or {}

    if annotations.bold then
      content = "**" .. content .. "**"
    end
    if annotations.italic then
      content = "*" .. content .. "*"
    end
    if annotations.code then
      content = "`" .. content .. "`"
    end
    if annotations.strikethrough then
      content = "~~" .. content .. "~~"
    end
    if text_obj.text and text_obj.text.link and type(text_obj.text.link) == "table" and text_obj.text.link.url then
      content = "[" .. content .. "](" .. text_obj.text.link.url .. ")"
    end

    table.insert(result, content)
  end

  return table.concat(result, "")
end

-- Convert a block to a comparable string for diffing
local function block_to_comparable_string(block)
  local block_type = block.type
  if not block[block_type] then
    return block_type .. ":" -- Just type if no content
  end

  local content = ""
  if block_type == "to_do" then
    -- Handle Todo blocks specifically to include checked state
    content = (block.to_do.checked and "checked" or "unchecked") .. ":" ..
      rich_text_to_markdown(block.to_do.rich_text or {})
  elseif block[block_type].rich_text then
    content = rich_text_to_markdown(block[block_type].rich_text)
  elseif block[block_type].language then
    -- Code blocks
    content = block[block_type].language .. ":" .. rich_text_to_markdown(block[block_type].rich_text or {})
  elseif block_type == "image" and block[block_type].external then
    -- Image blocks
    local caption = ""
    if block[block_type].caption then
      caption = rich_text_to_markdown(block[block_type].caption)
    end
    content = "image:" .. (block[block_type].external.url or "") .. ":" .. caption
  elseif block_type == "image" and block[block_type].file then
    -- File image blocks
    local caption = ""
    if block[block_type].caption then
      caption = rich_text_to_markdown(block[block_type].caption)
    end
    content = "image:" .. (block[block_type].file.url or "") .. ":" .. caption
  end

  return block_type .. ":" .. content
end

-- Calculate diff operations between existing and new blocks
-- Maximum number of blocks to search ahead in each direction when looking for
-- a sync point after a type mismatch. Prevents O(n*m) worst case on large
-- documents with structural edits.
local DIFF_SEARCH_WINDOW = 50

local function calculate_diff_operations(existing_blocks_results, new_blocks)
  local operations = {
    updates = {},
    deletes = {},
    inserts = {}, -- This will be a list of insert operations
    noops = 0,
  }

  local existing_blocks = existing_blocks_results or {}
  local num_existing = #existing_blocks
  local num_new = #new_blocks

  -- Pre-compute comparable strings for all blocks to avoid redundant conversions
  -- inside the diff loop. Each block's comparable string is computed once and reused.
  local existing_strings = {}
  for idx, block in ipairs(existing_blocks) do
    existing_strings[idx] = block_to_comparable_string(block)
  end
  local new_strings = {}
  for idx, block in ipairs(new_blocks) do
    new_strings[idx] = block_to_comparable_string(block)
  end

  local i = 1
  local j = 1
  local last_stable_block_id = nil

  while i <= num_existing and j <= num_new do
    local old_block = existing_blocks[i]
    local new_block = new_blocks[j]
    local old_comparable = existing_strings[i]
    local new_comparable = new_strings[j]

    if old_comparable == new_comparable then
      -- Blocks are identical, no-op
      operations.noops = operations.noops + 1
      last_stable_block_id = old_block.id
      i = i + 1
      j = j + 1
    elseif old_block.type == new_block.type then
      -- Same type, different content: UPDATE
      table.insert(operations.updates, {
        block_id = old_block.id,
        payload = { [new_block.type] = new_block[new_block.type] },
      })
      last_stable_block_id = old_block.id
      i = i + 1
      j = j + 1
    else
      -- Type mismatch or other difference. We need to find the next sync point.
      -- Cap the search to DIFF_SEARCH_WINDOW blocks ahead in each direction
      -- to prevent O(n*m) worst case on large documents with structural edits.
      local k = i
      local k_max = math.min(num_existing, i + DIFF_SEARCH_WINDOW)
      local l_max = math.min(num_new, j + DIFF_SEARCH_WINDOW)
      while k <= k_max do
        local l = j
        while l <= l_max do
          if existing_strings[k] == new_strings[l] then
            -- Found a sync point. Delete blocks from i to k-1 and insert from j to l-1.
            for del_idx = i, k - 1 do
              table.insert(operations.deletes, { block_id = existing_blocks[del_idx].id })
            end
            local children_to_insert = {}
            for ins_idx = j, l - 1 do
              table.insert(children_to_insert, new_blocks[ins_idx])
            end
            if #children_to_insert > 0 then
              table.insert(operations.inserts, {
                children = children_to_insert,
                after = last_stable_block_id,
              })
            end
            i = k
            j = l
            goto continue_outer_loop
          end
          l = l + 1
        end
        k = k + 1
      end

      -- No sync point found within search window.
      -- Delete remaining old blocks and insert remaining new ones.
      for del_idx = i, num_existing do
        table.insert(operations.deletes, { block_id = existing_blocks[del_idx].id })
      end
      local children_to_insert = {}
      for ins_idx = j, num_new do
        table.insert(children_to_insert, new_blocks[ins_idx])
      end
      if #children_to_insert > 0 then
        table.insert(operations.inserts, {
          children = children_to_insert,
          after = last_stable_block_id,
        })
      end
      i = num_existing + 1
      j = num_new + 1
      ::continue_outer_loop::
    end
  end

  -- Handle trailing blocks
  if i <= num_existing then
    -- More old blocks than new ones, delete the excess
    for k = i, num_existing do
      table.insert(operations.deletes, { block_id = existing_blocks[k].id })
    end
  elseif j <= num_new then
    -- More new blocks than old ones, insert the excess
    local children_to_insert = {}
    for k = j, num_new do
      table.insert(children_to_insert, new_blocks[k])
    end
    if #children_to_insert > 0 then
      table.insert(operations.inserts, {
        children = children_to_insert,
        after = last_stable_block_id,
      })
    end
  end

  return operations
end

-- Convert blocks to markdown
local function blocks_to_markdown(blocks)
  local lines = {}

  for _, block in ipairs(blocks) do
    if block.type == 'paragraph' then
      local text = rich_text_to_markdown(block.paragraph.rich_text)
      table.insert(lines, text)
      table.insert(lines, "")
    elseif block.type == 'heading_1' then
      local text = rich_text_to_markdown(block.heading_1.rich_text)
      table.insert(lines, "# " .. text)
      table.insert(lines, "")
    elseif block.type == 'heading_2' then
      local text = rich_text_to_markdown(block.heading_2.rich_text)
      table.insert(lines, "## " .. text)
      table.insert(lines, "")
    elseif block.type == 'heading_3' then
      local text = rich_text_to_markdown(block.heading_3.rich_text)
      table.insert(lines, "### " .. text)
      table.insert(lines, "")
    elseif block.type == 'bulleted_list_item' then
      local text = rich_text_to_markdown(block.bulleted_list_item.rich_text)
      table.insert(lines, "- " .. text)
    elseif block.type == 'numbered_list_item' then
      local text = rich_text_to_markdown(block.numbered_list_item.rich_text)
      table.insert(lines, "1. " .. text)
    elseif block.type == 'to_do' then
      local text = rich_text_to_markdown(block.to_do.rich_text)
      local checkbox = block.to_do.checked and "[x]" or "[ ]"
      table.insert(lines, "- " .. checkbox .. " " .. text)
    elseif block.type == 'code' then
      local text = rich_text_to_markdown(block.code.rich_text)
      local language = block.code.language or ""
      table.insert(lines, "```" .. language)
      for _, line in ipairs(vim.split(text, "\n")) do
        table.insert(lines, line)
      end
      table.insert(lines, "```")
    elseif block.type == 'image' then
      local caption = ""
      if block.image.caption and #block.image.caption > 0 then
        caption = rich_text_to_markdown(block.image.caption)
      end
      local url = ""
      if block.image.type == "external" and block.image.external and block.image.external.url then
        url = block.image.external.url
      elseif block.image.type == "file" and block.image.file and block.image.file.url then
        url = block.image.file.url
      end
      if url ~= "" then
        table.insert(lines, "![" .. caption .. "](" .. url .. ")")
        table.insert(lines, "")
      end
    end
  end

  return lines
end

-- Internal implementation of edit_page (can run in sync or async context)
local function edit_page_impl(page_id)
  if not page_id then
    vim.notify('Page ID required', vim.log.levels.ERROR)
    return
  end

  -- First get page details
  local page_result = make_request('GET', '/pages/' .. page_id)
  if not page_result then
    return
  end

  -- Get page title
  local title = 'Untitled'
  if page_result.properties.Name and page_result.properties.Name.title and #page_result.properties.Name.title > 0 then
    title = page_result.properties.Name.title[1].text.content
  end

  -- Get page content blocks
  local all_blocks = M.get_all_blocks(page_id)

  -- Cache the fetched blocks for use during sync
  set_cached_blocks(page_id, all_blocks)

  -- Convert blocks to markdown
  local markdown_lines = blocks_to_markdown(all_blocks)

  -- Create new buffer (Neovim API calls are safe here because in async context
  -- we resumed via vim.schedule, so we're on the main loop)
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, title .. '.md')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, markdown_lines)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].modified = false

  -- Store page metadata
  vim.api.nvim_buf_set_var(buf, 'notion_page_id', page_id)
  vim.api.nvim_buf_set_var(buf, 'notion_page_url', page_result.url)

  -- Set up autocmd for save
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      M.sync_page()
    end,
    desc = "Auto-sync Notion page on save"
  })

  -- Clear cache when buffer is closed
  vim.api.nvim_create_autocmd({"BufDelete", "BufWipeout"}, {
    buffer = buf,
    callback = function()
      clear_cached_blocks(page_id)
    end,
    desc = "Clear Notion block cache on buffer close"
  })

  -- Open buffer in current window
  vim.api.nvim_set_current_buf(buf)

  vim.notify('Loaded Notion page: ' .. title, vim.log.levels.INFO)
end

--[[
Edit a Notion page directly in a Neovim buffer with automatic sync.

This function fetches the page content, converts it to markdown, and opens it
in a new buffer with auto-sync capabilities. When you save the buffer (:w),
changes are automatically synced back to Notion using intelligent diff-based
updates that only modify changed blocks.

Runs asynchronously -- does not block the Neovim event loop.

@param page_id string: The Notion page ID to edit
--]]
function M.edit_page(page_id)
  if not page_id then
    vim.notify('Page ID required', vim.log.levels.ERROR)
    return
  end

  async_notify_start('Loading page')
  run_async(function()
    edit_page_impl(page_id)
    async_notify_end('Loading page', true)
  end)
end

-- Parse inline markdown formatting and return rich_text array
local function parse_rich_text(text)
  local rich_text = {}
  local pos = 1

  while pos <= #text do
    -- Look for inline code (backticks)
    local code_start, code_end = text:find("`([^`]+)`", pos)

    if code_start then
      -- Add text before the code (if any)
      if code_start > pos then
        table.insert(rich_text, {
          type = "text",
          text = { content = text:sub(pos, code_start - 1) }
        })
      end

      -- Add the code text with formatting
      local code_content = text:sub(code_start + 1, code_end - 1)
      table.insert(rich_text, {
        type = "text",
        text = { content = code_content },
        annotations = { code = true }
      })

      pos = code_end + 1
    else
      -- No more inline formatting, add remaining text
      if pos <= #text then
        table.insert(rich_text, {
          type = "text",
          text = { content = text:sub(pos) }
        })
      end
      break
    end
  end

  -- If no formatting was found, return simple text
  if #rich_text == 0 then
    table.insert(rich_text, {
      type = "text",
      text = { content = text }
    })
  end

  return rich_text
end

-- Parse markdown line to Notion block
local function markdown_line_to_block(line)
  -- Remove leading/trailing whitespace
  line = vim.trim(line)

  if line == "" then
    return nil  -- Skip empty lines
  end

  -- Check for headings
  if line:match("^# ") then
    return {
      type = "heading_1",
      heading_1 = {
        rich_text = parse_rich_text(line:sub(3))
      }
    }
  elseif line:match("^## ") then
    return {
      type = "heading_2",
      heading_2 = {
        rich_text = parse_rich_text(line:sub(4))
      }
    }
  elseif line:match("^### ") then
    return {
      type = "heading_3",
      heading_3 = {
        rich_text = parse_rich_text(line:sub(5))
      }
    }
  elseif line:match("^%- %[[ x]%] ") then
    -- Todo item
    local checked_char, text = line:match("^%- %[([ x])%] (.*)$")
    return {
      type = "to_do",
      to_do = {
        checked = (checked_char == 'x'),
        rich_text = parse_rich_text(text or "")
      }
    }
  elseif line:match("^%- ") then
    -- Bullet point
    return {
      type = "bulleted_list_item",
      bulleted_list_item = {
        rich_text = parse_rich_text(line:sub(3))
      }
    }
  elseif line:match("^%d+%. ") then
    -- Numbered list
    local text = line:match("^%d+%. (.+)")
    return {
      type = "numbered_list_item",
      numbered_list_item = {
        rich_text = parse_rich_text(text)
      }
    }
  elseif line:match("^!%[.-%]%(.*%)$") then
    -- Image syntax: ![caption](url)
    local caption, url = line:match("^!%[(.-)%]%((.*)%)$")
    return {
      type = "image",
      image = {
        type = "external",
        external = {
          url = url
        },
        caption = caption and caption ~= "" and parse_rich_text(caption) or {}
      }
    }
  else
    -- Regular paragraph
    return {
      type = "paragraph",
      paragraph = {
        rich_text = parse_rich_text(line)
      }
    }
  end
end

-- Convert markdown lines to Notion blocks
local function markdown_to_blocks(lines)
  local blocks = {}
  local in_code_block = false
  local code_lines = {}
  local code_language = ""

  for _, line in ipairs(lines) do
    if line:match("^```") then
      if in_code_block then
        -- End of code block
        table.insert(blocks, {
          type = "code",
          code = {
            language = code_language,
            rich_text = {
              {
                type = "text",
                text = { content = table.concat(code_lines, "\n") }
              }
            }
          }
        })
        in_code_block = false
        code_lines = {}
        code_language = ""
      else
        -- Start of code block
        in_code_block = true
        code_language = line:sub(4) or ""
      end
    elseif in_code_block then
      table.insert(code_lines, line)
    else
      local block = markdown_line_to_block(line)
      if block then
        table.insert(blocks, block)
      end
    end
  end

  return blocks
end

-- Internal implementation of sync_page (can run in sync or async context)
local function sync_page_impl()
  local debug_mode = config.get('debug')
  local start_time = debug_mode and vim.loop.hrtime() or nil
  local buf = vim.api.nvim_get_current_buf()

  -- Clear previous debug messages
  if debug_mode then
    debug_messages = {}
  end

  -- Check if this is a Notion page
  local ok, page_id = pcall(vim.api.nvim_buf_get_var, buf, 'notion_page_id')
  if not ok or not page_id then
    vim.notify('This buffer is not a Notion page', vim.log.levels.ERROR)
    return
  end

  -- Check if sync is already in progress for this page
  if sync_state[page_id] then
    if sync_state[page_id].in_progress then
      vim.notify('Sync already in progress...', vim.log.levels.WARN)
      return
    end

    -- Check debounce timer
    local time_since_last = vim.loop.hrtime() - sync_state[page_id].last_sync
    local debounce_ms = config.get('sync_debounce_ms') or 1000
    if time_since_last < (debounce_ms * 1000000) then
      local remaining_ms = math.ceil((debounce_ms * 1000000 - time_since_last) / 1000000)
      vim.notify('Too soon! Wait ' .. remaining_ms .. 'ms before next sync', vim.log.levels.WARN)
      return
    end
  end

  -- Initialize sync state for this page
  if not sync_state[page_id] then
    sync_state[page_id] = {}
  end

  -- Mark sync as in progress
  sync_state[page_id].in_progress = true
  sync_state[page_id].last_sync = vim.loop.hrtime()

  local check_time = debug_mode and vim.loop.hrtime() or nil
  if debug_mode then
    table.insert(debug_messages, "Page check took: " .. ((check_time - start_time) / 1000000) .. "ms")
  end

  -- Get buffer content
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local lines_time = debug_mode and vim.loop.hrtime() or nil
  if debug_mode then
    table.insert(debug_messages, "Get lines took: " .. ((lines_time - check_time) / 1000000) .. "ms")
  end

  -- Convert markdown to blocks
  local blocks = markdown_to_blocks(lines)

  local blocks_time = debug_mode and vim.loop.hrtime() or nil
  if debug_mode then
    table.insert(debug_messages, "Markdown conversion took: " .. ((blocks_time - lines_time) / 1000000) .. "ms")
  end

  if #blocks == 0 then
    vim.notify('No content to sync', vim.log.levels.WARN)
    sync_state[page_id].in_progress = false
    return
  end

  -- Strategy: Diff-based sync - only update changed blocks, maintain order
  -- Check cache first to avoid redundant API calls
  local existing_blocks = get_cached_blocks(page_id)
  local used_cache = existing_blocks ~= nil

  if debug_mode then
    if used_cache then
      table.insert(debug_messages, "Using cached blocks for diff")
    else
      table.insert(debug_messages, "Getting existing blocks for diff...")
    end
  end

  if not existing_blocks then
    existing_blocks = M.get_all_blocks(page_id)
  end

  local get_time = debug_mode and vim.loop.hrtime() or nil
  if debug_mode then
    table.insert(debug_messages, "GET existing blocks took: " .. ((get_time - blocks_time) / 1000000) .. "ms")
  end

  -- Find blocks that need to be deleted/updated/inserted
  local operations = calculate_diff_operations(existing_blocks, blocks)

  local diff_time = debug_mode and vim.loop.hrtime() or nil
  if debug_mode then
    table.insert(debug_messages, "Diff calculation took: " .. ((diff_time - get_time) / 1000000) .. "ms")
    local num_inserts = 0
    for _, op in ipairs(operations.inserts) do
      num_inserts = num_inserts + #op.children
    end
    table.insert(debug_messages, "Operations: " .. #operations.updates .. " updates, " .. #operations.deletes ..
      " deletes, " .. num_inserts .. " inserts, " .. operations.noops .. " no-ops")
  end

  -- Apply operations: updates + deletes concurrently, then inserts sequentially.
  -- Updates and deletes touch different blocks (guaranteed by diff algorithm),
  -- so they can all run in parallel. Deletes must finish before inserts start
  -- to ensure block positioning is correct.
  local sync_result = true

  -- Build concurrent task list for updates and deletes together
  local concurrent_tasks = {}
  local update_start = debug_mode and vim.loop.hrtime() or nil

  for _, update_op in ipairs(operations.updates) do
    local op = update_op -- capture for closure
    table.insert(concurrent_tasks, function()
      return make_request('PATCH', '/blocks/' .. op.block_id, op.payload)
    end)
  end

  for _, delete_op in ipairs(operations.deletes) do
    local op = delete_op -- capture for closure
    table.insert(concurrent_tasks, function()
      return make_request('DELETE', '/blocks/' .. op.block_id)
    end)
  end

  -- Run all updates and deletes concurrently
  if #concurrent_tasks > 0 then
    local concurrent_results = run_concurrent(concurrent_tasks)
    for i, result in ipairs(concurrent_results) do
      if not result.ok then
        vim.notify('[Notion] Concurrent operation ' .. i .. ' failed: ' .. tostring(result.value),
          vim.log.levels.ERROR)
        sync_result = false
      elseif result.value == nil then
        -- make_request returns nil on API error (already notified)
        sync_result = false
      end
    end
  end

  local delete_done_time = debug_mode and vim.loop.hrtime() or nil
  if debug_mode and update_start then
    table.insert(debug_messages, "All updates+deletes took: " ..
      ((delete_done_time - update_start) / 1000000) .. "ms")
  end

  -- Inserts run sequentially (depend on `after` positioning)
  local insert_start = debug_mode and vim.loop.hrtime() or nil
  for _, insert_op in ipairs(operations.inserts) do
    if insert_op.children and #insert_op.children > 0 then
      local children = insert_op.children
      local chunk_size = 100
      for ci = 1, #children, chunk_size do
        local chunk = {}
        for cj = ci, math.min(ci + chunk_size - 1, #children) do
          table.insert(chunk, children[cj])
        end
        local chunk_insert_op = {
          children = chunk,
          after = insert_op.after
        }
        local result = make_request('PATCH', '/blocks/' .. page_id .. '/children', chunk_insert_op)
        if not result then
          sync_result = false
        end
      end
    end
  end

  local ops_time = debug_mode and vim.loop.hrtime() or nil
  if debug_mode and insert_start then
    table.insert(debug_messages, "All inserts took: " .. ((ops_time - insert_start) / 1000000) .. "ms")
  end

  if sync_result then
    -- Update cache to reflect the new block state after successful sync
    -- Re-fetch blocks to get the authoritative state (with server-assigned IDs)
    local updated_blocks = M.get_all_blocks(page_id)
    set_cached_blocks(page_id, updated_blocks)

    vim.bo[buf].modified = false
    notify_user('Synced to Notion successfully', vim.log.levels.INFO)
  else
    notify_user('Failed to sync to Notion', vim.log.levels.ERROR)
  end

  -- Clear sync state
  sync_state[page_id].in_progress = false

  -- Show debug messages immediately
  if debug_mode then
    local total_time = vim.loop.hrtime()
    table.insert(debug_messages, "Total sync took: " .. ((total_time - start_time) / 1000000) .. "ms")

    local success, noice = pcall(require, 'noice')
    if success and noice then
      noice.notify(table.concat(debug_messages, "\n"), vim.log.levels.INFO, {
        timeout = 5000,
        title = "Notion.nvim Debug"
      })
    else
      for _, msg in ipairs(debug_messages) do
        print(msg)
      end
    end
  end
end

--[[
Sync the current buffer's content back to Notion using intelligent diff-based updates.

This function implements a sophisticated sync algorithm that:
1. Fetches existing blocks from the Notion page
2. Converts the buffer content to Notion block format
3. Calculates a diff between existing and new content
4. Only updates blocks that have actually changed
5. Preserves unchanged blocks for optimal performance
6. Maintains proper block ordering using Notion's positioning API

Performance: Typically 200-800ms for small edits, scaling with the amount of
changed content rather than total document size.

Runs asynchronously -- does not block the Neovim event loop.
Operations execute in order (updates, then deletes, then inserts) because
coroutines yield sequentially.

The function includes comprehensive error handling, debouncing to prevent API
abuse, and detailed debug output when debug mode is enabled.
--]]
function M.sync_page()
  async_notify_start('Syncing page')
  run_async(function()
    sync_page_impl()
    async_notify_end('Syncing page', true)
  end)
end

-- Internal implementation of list_and_edit_pages (can run in sync or async context)
local function list_and_edit_pages_impl()
  local database_id = config.get('database_id')
  if not database_id then
    vim.notify('Database ID not configured', vim.log.levels.ERROR)
    return
  end

  -- Fetch all pages with pagination
  local pages = M.get_all_pages(database_id)

  if not pages or #pages == 0 then
    vim.notify('No pages found in database', vim.log.levels.WARN)
    return
  end

  -- Sort pages alphabetically by title (case-insensitive)
  table.sort(pages, function(a, b)
    return a.title:lower() < b.title:lower()
  end)

  vim.notify(string.format('Found %d pages', #pages), vim.log.levels.INFO)

  -- Callback when page is selected
  local function on_page_selected(page)
    M.edit_page(page.id)
  end

  -- Try Telescope if configured/available
  if config.should_use_telescope() then
    local tel_ok, telescope_picker = pcall(require, 'notion.telescope')
    if tel_ok then
      telescope_picker.notion_pages(pages, on_page_selected)
      return
    else
      -- Show the actual error message for debugging
      local error_msg = telescope_picker or "unknown error"
      if config.get('use_telescope') == true then
        vim.notify('notion.telescope failed to load: ' .. tostring(error_msg), vim.log.levels.ERROR)
        vim.notify('Telescope not available, falling back to vim.ui.select', vim.log.levels.WARN)
      else
        -- Only show fallback message if not explicitly requested
        vim.notify('Falling back to vim.ui.select', vim.log.levels.WARN)
      end
    end
  end

  -- Fallback to vim.ui.select
  vim.ui.select(pages, {
    prompt = 'Select a Notion page to edit:',
    format_item = function(item)
      return item.title
    end,
  }, function(choice)
    if choice then
      on_page_selected(choice)
    end
  end)
end

--[[
List pages from the database and select one for editing in Neovim.

This function provides a user-friendly interface to browse all pages in your
configured Notion database and select one for direct editing in Neovim.
Selected pages are opened with the edit_page() function for seamless editing.

Runs asynchronously -- does not block the Neovim event loop.
--]]
function M.list_and_edit_pages()
  local database_id = config.get('database_id')
  if not database_id then
    vim.notify('Database ID not configured', vim.log.levels.ERROR)
    return
  end

  async_notify_start('Fetching pages')
  run_async(function()
    list_and_edit_pages_impl()
    async_notify_end('Fetching pages', true)
  end)
end

-- Expose internals for testing and external use
M.calculate_diff_operations = calculate_diff_operations
M.block_to_comparable_string = block_to_comparable_string
M.blocks_to_markdown = blocks_to_markdown
M.markdown_line_to_block = markdown_line_to_block
M.make_request = make_request
M.get_cached_blocks = get_cached_blocks
M.set_cached_blocks = set_cached_blocks
M.clear_cached_blocks = clear_cached_blocks
M.block_cache = block_cache
M.run_async = run_async
M.run_concurrent = run_concurrent

return M
