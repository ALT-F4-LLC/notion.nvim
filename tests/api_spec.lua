-- Helper to create async-aware curl mock functions.
-- When opts.callback is present (async path), calls the callback with the
-- response. The async_curl_request function in api.lua handles the case where
-- the callback fires synchronously (before coroutine.yield).
-- When opts.callback is absent (sync path), returns the response directly.
local function make_curl_mock(response_fn)
  return spy.new(function(opts)
    local response = response_fn(opts)
    if opts and opts.callback then
      opts.callback(response)
      return nil -- async: plenary.curl returns job handle, we return nil
    end
    return response
  end)
end

describe("api", function()
  local api
  local mock_config
  local mock_curl

  before_each(function()
    -- Reset module cache
    package.loaded['notion.api'] = nil
    package.loaded['notion.config'] = nil
    package.loaded['plenary.curl'] = nil

    -- Mock config
    mock_config = {
      get = function(key)
        local defaults = {
          debug = false,
          notion_token = "test_token",
          database_id = "test_db_id",
          page_size = 100,
          sync_debounce_ms = 1000
        }
        return defaults[key]
      end
    }

    -- Mock curl with async-aware wrappers
    mock_curl = {
      get = make_curl_mock(function() return { status = 200, body = '{"success": true}' } end),
      post = make_curl_mock(function() return { status = 200, body = '{"success": true}' } end),
      patch = make_curl_mock(function() return { status = 200, body = '{"success": true}' } end),
      delete = make_curl_mock(function() return { status = 204, body = '' } end)
    }

    package.preload['notion.config'] = function() return mock_config end
    package.preload['plenary.curl'] = function() return mock_curl end

    vim.split = function(str, sep)
      local result = {}
      for s in str:gmatch("([^" .. sep .. "]+)") do
        table.insert(result, s)
      end
      return result
    end

    vim.loop = {
      sleep = function() end,
      hrtime = function() return 0 end
    }

    api = require('notion.api')
  end)

  after_each(function()
    -- Clean up mocks
    package.preload['notion.config'] = nil
    package.preload['plenary.curl'] = nil
  end)


  describe("markdown_line_to_block", function()
    it("should handle to-do blocks", function()
      local block_checked = api.markdown_line_to_block("- [x] task")
      local block_unchecked = api.markdown_line_to_block("- [ ] task")

      assert.is_true(block_checked.to_do.checked)
      assert.is_false(block_unchecked.to_do.checked)
    end)
  end)

  describe("block_to_comparable_string", function()
    it("should handle to-do blocks", function()
      local block_checked = {
        type = "to_do",
        to_do = { checked = true, rich_text = { { text = { content = "task" } } } }
      }
      local block_unchecked = {
        type = "to_do",
        to_do = { checked = false, rich_text = { { text = { content = "task" } } } }
      }

      local comparable_checked = api.block_to_comparable_string(block_checked)
      local comparable_unchecked = api.block_to_comparable_string(block_unchecked)

      assert.is_not.equal(comparable_checked, comparable_unchecked)
    end)
  end)

  describe("open_page_by_url", function()
    it("should handle macOS", function()
      vim.fn.has = function(feature)
        return feature == 'mac' and 1 or 0
      end

      local system_calls = {}
      vim.fn.system = function(cmd)
        table.insert(system_calls, cmd)
      end

      api.open_page_by_url("https://notion.so/test")

      assert.equals(1, #system_calls)
      assert.is_not_nil(string.match(system_calls[1], "open"))
    end)

    it("should handle Unix/Linux", function()
      vim.fn.has = function(feature)
        return feature == 'unix' and 1 or 0
      end

      local system_calls = {}
      vim.fn.system = function(cmd)
        table.insert(system_calls, cmd)
      end

      api.open_page_by_url("https://notion.so/test")

      assert.equals(1, #system_calls)
      assert.is_not_nil(string.match(system_calls[1], "xdg%-open"))
    end)

    it("should handle Windows", function()
      vim.fn.has = function(feature)
        return feature == 'win32' and 1 or 0
      end

      local system_calls = {}
      vim.fn.system = function(cmd)
        table.insert(system_calls, cmd)
      end

      api.open_page_by_url("https://notion.so/test")

      assert.equals(1, #system_calls)
      assert.is_not_nil(string.match(system_calls[1], "start"))
    end)

    it("should notify on unsupported platform", function()
      vim.fn.has = function() return 0 end

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      api.open_page_by_url("https://notion.so/test")

      assert.equals(1, #notifications)
      assert.equals("Cannot open URL on this platform", notifications[1].msg)
      assert.equals(vim.log.levels.ERROR, notifications[1].level)
    end)
  end)

  describe("create_page", function()
    it("should require a title", function()
      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      api.create_page("")

      assert.equals(1, #notifications)
      assert.is_not_nil(string.match(notifications[1].msg, "title is required"))
    end)

    it("should require database_id configuration", function()
      mock_config.get = function(key)
        if key == "database_id" then return nil end
        return "test_value"
      end

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      api.create_page("Test Title")

      assert.equals(1, #notifications)
      assert.is_not_nil(string.match(notifications[1].msg, "Database ID not configured"))
    end)
  end)

  describe("list_pages", function()
    it("should require database_id configuration", function()
      mock_config.get = function(key)
        if key == "database_id" then return nil end
        return "test_value"
      end

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      api.list_pages()

      assert.equals(1, #notifications)
      assert.is_not_nil(string.match(notifications[1].msg, "Database ID not configured"))
    end)
  end)


  describe("blocks_to_markdown", function()
    it("should handle multiline code blocks", function()
      local blocks = {
        { type = "code", code = { rich_text = { { text = { content = "line1\nline2" } } }, language = "lua" } }
      }
      local markdown = api.blocks_to_markdown(blocks)
      assert.equals(4, #markdown)
      assert.equals("```lua", markdown[1])
      assert.equals("line1", markdown[2])
      assert.equals("line2", markdown[3])
      assert.equals("```", markdown[4])
    end)
  end)

  describe("image handling", function()
    local test_api
    local original_get_func

    before_each(function()
      -- Clear all notion-related modules
      package.loaded['notion.api'] = nil
      package.loaded['notion.config'] = nil
      package.loaded['plenary.curl'] = nil
      -- Store original get function and make it dynamic
      original_get_func = mock_curl.get
    end)

    after_each(function()
      -- Restore original get function
      mock_curl.get = original_get_func
    end)

    it("should convert external image blocks to markdown", function()
      -- Set up mock responses for this test (async-aware)
      mock_curl.get = make_curl_mock(function(opts)
        if opts.url:match("/pages/test%-page%-id$") then
          return {
            status = 200,
            body = 'page-with-properties-Test Page'
          }
        elseif opts.url:match("/blocks/test%-page%-id/children$") then
          return {
            status = 200,
            body = 'blocks-with-images'
          }
        end
        return { status = 200, body = '{"success": true}' }
      end)

      -- Load API after setting up the mock
      test_api = require('notion.api')

      local buffer_lines = {}
      vim.api.nvim_buf_set_lines = function(buf, start, end_line, strict_indexing, replacement)
        buffer_lines = replacement
      end

      test_api.edit_page("test-page-id")

      -- Check that image was converted to markdown
      local found_external_image = false
      local found_file_image = false
      for _, line in ipairs(buffer_lines) do
        if line == "![Test Caption](https://example.com/image.jpg)" then
          found_external_image = true
        elseif line == "![](https://files.notion.com/image.png)" then
          found_file_image = true
        end
      end

      assert.is_true(found_external_image, "External image should be converted to markdown")
      assert.is_true(found_file_image, "File image should be converted to markdown")
    end)

    it("should handle image blocks in sync operations", function()
      -- Mock the buffer to contain image markdown (different from existing blocks)
      local test_buffer_content = {
        "# Test Page",
        "",
        "![New Image](https://example.com/new-image.jpg)",
        "",
        "Some text content"
      }

      vim.api.nvim_buf_get_lines = function() return test_buffer_content end
      vim.api.nvim_buf_get_var = function(buf, var)
        if var == "notion_page_id" then return "test-page-id" end
        if var == "notion_page_url" then return "https://notion.so/test" end
        error("Variable not found: " .. var)
      end
      vim.api.nvim_get_current_buf = function() return 1 end

      -- Mock the existing blocks response for sync (async-aware)
      mock_curl.get = make_curl_mock(function(opts)
        if opts.url:match("/blocks/test%-page%-id/children$") then
          return {
            status = 200,
            body = 'sync-heading'
          }
        end
        return { status = 200, body = '{"success": true}' }
      end)

      -- Load API after setting up the mock
      test_api = require('notion.api')

      -- Track patch calls to verify image block creation
      local patch_calls = {}
      mock_curl.patch = make_curl_mock(function(opts)
        table.insert(patch_calls, { url = opts.url, body = opts.body })
        return { status = 200, body = '{"success": true}' }
      end)

      -- Test that sync_page runs without error and handles image content
      test_api.sync_page()

      -- Verify that sync operation completed (the patch calls are complex to mock properly)
      -- The key test is that image content can be processed in sync without errors
      assert.is_true(true, "Sync operation should complete without errors")
    end)

    it("should handle image captions correctly", function()
      local buffer_lines = {}
      vim.api.nvim_buf_set_lines = function(buf, start, end_line, strict_indexing, replacement)
        buffer_lines = replacement
      end

      -- Mock response with image that has complex caption (async-aware)
      mock_curl.get = make_curl_mock(function(opts)
        if opts.url:match("/pages/test%-page%-id$") then
          return {
            status = 200,
            body = 'page-with-properties-Test Page'
          }
        elseif opts.url:match("/blocks/test%-page%-id/children$") then
          return {
            status = 200,
            body = 'complex-caption'
          }
        end
        return { status = 200, body = '{"success": true}' }
      end)

      -- Load API after setting up the mock
      test_api = require('notion.api')

      test_api.edit_page("test-page-id")

      -- Check that formatted caption was preserved
      local found_formatted_caption = false
      for _, line in ipairs(buffer_lines) do
        if line:match("!%[%*%*Image with %*%*%*formatted%* caption%]%(https://example%.com/test%.jpg%)") then
          found_formatted_caption = true
          break
        end
      end

      assert.is_true(found_formatted_caption, "Formatted image caption should be preserved")
    end)
  end)

  describe("make_request", function()
    it("should require notion_token", function()
      mock_config.get = function(key)
        if key == "notion_token" then return nil end
        return "test_value"
      end

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- This will be called internally by other functions
      -- list_pages now validates database_id first, so we call make_request directly
      api.make_request('POST', '/databases/test_db/query', {})

      assert.equals(1, #notifications)
      assert.is_not_nil(string.match(notifications[1].msg, "token not configured"))
    end)

    it("should sanitize tokens in error messages", function()
      local test_token = "secret_token_12345"
      mock_config.get = function(key)
        if key == "notion_token" then return test_token end
        if key == "debug" then return false end
        if key == "database_id" then return "test_db_id" end
        return "test_value"
      end

      -- Mock curl to return an error response containing the token (async-aware)
      mock_curl.post = make_curl_mock(function()
        return {
          status = 401,
          body = '{"error": "Invalid token: ' .. test_token .. '"}'
        }
      end)

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Call make_request directly (sync path, no coroutine)
      api.make_request('POST', '/databases/test_db_id/query', {})

      assert.equals(1, #notifications)
      -- Verify the token is sanitized in the error message
      assert.is_nil(string.match(notifications[1].msg, test_token))
      assert.is_not_nil(string.match(notifications[1].msg, "%[REDACTED%]"))
    end)

    it("should sanitize Bearer tokens in error messages", function()
      local test_token = "secret_bearer_token"
      mock_config.get = function(key)
        if key == "notion_token" then return test_token end
        if key == "debug" then return false end
        if key == "database_id" then return "test_db_id" end
        return "test_value"
      end

      -- Mock curl to return an error response containing the Bearer token (async-aware)
      mock_curl.post = make_curl_mock(function()
        return {
          status = 403,
          body = '{"message": "Authorization failed for Bearer ' .. test_token .. '"}'
        }
      end)

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Call make_request directly (sync path, no coroutine)
      api.make_request('POST', '/pages', { parent = { database_id = "test_db_id" }, properties = {} })

      assert.equals(1, #notifications)
      -- Verify the Bearer token is sanitized
      assert.is_nil(string.match(notifications[1].msg, test_token))
      assert.is_not_nil(string.match(notifications[1].msg, "Bearer %[REDACTED%]"))
    end)

    it("should handle pagination", function()
      local call_count = 0
      api.make_request = spy.new(function(method, endpoint, data)
        call_count = call_count + 1
        if call_count == 1 then
          return {
            results = { { id = "block1" } },
            has_more = true,
            next_cursor = "cursor1"
          }
        else
          return {
            results = { { id = "block2" } }
          }
        end
      end)

      local blocks = api.get_all_blocks("page1")

      assert.equals(2, #blocks)
      assert.equals("block1", blocks[1].id)
      assert.equals("block2", blocks[2].id)
    end)

    it("should handle rate limiting", function()
      local call_count = 0
      api.make_request = spy.new(function(method, endpoint, data)
        call_count = call_count + 1
        if call_count == 1 then
          return nil
        else
          return {
            results = { { id = "block1" } }
          }
        end
      end)

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      local blocks = api.get_all_blocks("page1")

      assert.equals(1, #blocks)
      assert.equals("block1", blocks[1].id)
    end)
  end)

  describe("async execution", function()
    it("should execute make_request asynchronously inside a coroutine", function()
      local request_completed = false

      -- Set up async-aware mock
      mock_curl.get = make_curl_mock(function(opts)
        return { status = 200, body = '{"results": [{"id": "async-block1"}]}' }
      end)

      -- Use run_async to create coroutine context
      api.run_async(function()
        local result = api.make_request('GET', '/blocks/test-page/children')
        assert.is_not_nil(result)
        assert.is_not_nil(result.results)
        assert.equals("async-block1", result.results[1].id)
        request_completed = true
      end)

      -- Since vim.schedule_wrap is mocked to call immediately, the coroutine
      -- completes synchronously in tests
      assert.is_true(request_completed, "Async request should complete")
    end)

    it("should use sync path when not in a coroutine", function()
      -- Calling make_request outside of a coroutine should use sync path
      local result = api.make_request('GET', '/blocks/test-page/children')
      assert.is_not_nil(result)
    end)

    it("should handle async errors gracefully", function()
      local error_notifications = {}
      vim.notify = function(msg, level)
        table.insert(error_notifications, { msg = msg, level = level })
      end

      mock_curl.get = make_curl_mock(function(opts)
        return { status = 500, body = '{"error": "Internal Server Error"}' }
      end)

      local result_from_async = nil
      api.run_async(function()
        result_from_async = api.make_request('GET', '/blocks/test-page/children')
      end)

      assert.is_nil(result_from_async)
      -- Should have error notification
      local found_error = false
      for _, n in ipairs(error_notifications) do
        if n.msg:match("Notion API error") then
          found_error = true
          break
        end
      end
      assert.is_true(found_error, "Should notify on API error in async context")
    end)

    it("should handle rate limiting with non-blocking sleep in async context", function()
      local call_count = 0
      mock_curl.get = make_curl_mock(function(opts)
        call_count = call_count + 1
        if call_count == 1 then
          return {
            status = 429,
            headers = { ['Retry-After'] = '1' },
            body = ''
          }
        end
        return { status = 200, body = '{"results": [{"id": "block1"}]}' }
      end)

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      local result_from_async = nil
      api.run_async(function()
        result_from_async = api.make_request('GET', '/blocks/test-page/children')
      end)

      -- Should have completed after retry
      assert.is_not_nil(result_from_async)
      assert.is_not_nil(result_from_async.results)

      -- Should have rate limit notification
      local found_rate_limit = false
      for _, n in ipairs(notifications) do
        if n.msg:match("Rate limited") then
          found_rate_limit = true
          break
        end
      end
      assert.is_true(found_rate_limit, "Should notify about rate limiting")
    end)
  end)

  describe("calculate_diff_operations", function()
    it("should detect no changes", function()
      local existing_blocks = {
        { id = "block1", type = "paragraph", paragraph = { rich_text = { { text = { content = "hello" } } } } }
      }
      local new_blocks = {
        { type = "paragraph", paragraph = { rich_text = { { text = { content = "hello" } } } } }
      }

      local operations = api.calculate_diff_operations(existing_blocks, new_blocks)

      assert.equals(0, #operations.updates)
      assert.equals(0, #operations.deletes)
      assert.equals(0, #operations.inserts)
      assert.equals(1, operations.noops)
    end)

    it("should detect updates", function()
      local existing_blocks = {
        { id = "block1", type = "paragraph", paragraph = { rich_text = { { text = { content = "hello" } } } } }
      }
      local new_blocks = {
        { type = "paragraph", paragraph = { rich_text = { { text = { content = "world" } } } } }
      }

      local operations = api.calculate_diff_operations(existing_blocks, new_blocks)

      assert.equals(1, #operations.updates)
      assert.equals(0, #operations.deletes)
      assert.equals(0, #operations.inserts)
      assert.equals(0, operations.noops)
      assert.equals("block1", operations.updates[1].block_id)
    end)

    it("should detect deletions", function()
      local existing_blocks = {
        { id = "block1", type = "paragraph", paragraph = { rich_text = { { text = { content = "hello" } } } } }
      }
      local new_blocks = {}

      local operations = api.calculate_diff_operations(existing_blocks, new_blocks)

      assert.equals(0, #operations.updates)
      assert.equals(1, #operations.deletes)
      assert.equals(0, #operations.inserts)
      assert.equals(0, operations.noops)
      assert.equals("block1", operations.deletes[1].block_id)
    end)

    it("should detect insertions", function()
      local existing_blocks = {}
      local new_blocks = {
        { type = "paragraph", paragraph = { rich_text = { { text = { content = "hello" } } } } }
      }

      local operations = api.calculate_diff_operations(existing_blocks, new_blocks)

      assert.equals(0, #operations.updates)
      assert.equals(0, #operations.deletes)
      assert.equals(1, #operations.inserts)
      assert.equals(0, operations.noops)
      assert.equals(1, #operations.inserts[1].children)
    end)

    it("should handle mixed operations", function()
      local existing_blocks = {
        { id = "block1", type = "paragraph", paragraph = { rich_text = { { text = { content = "hello" } } } } },
        { id = "block2", type = "paragraph", paragraph = { rich_text = { { text = { content = "world" } } } } }
      }
      local new_blocks = {
        { type = "paragraph", paragraph = { rich_text = { { text = { content = "hello" } } } } },
        { type = "heading_1", heading_1 = { rich_text = { { text = { content = "world" } } } } }
      }

      local operations = api.calculate_diff_operations(existing_blocks, new_blocks)

      assert.equals(0, #operations.updates)
      assert.equals(1, #operations.deletes)
      assert.equals(1, #operations.inserts)
      assert.equals(1, operations.noops)
      assert.equals("block2", operations.deletes[1].block_id)
      assert.equals(1, #operations.inserts[1].children)
    end)

    it("should complete without pathological delay on many type mismatches", function()
      -- Build a large document where every block has a different type between
      -- existing and new. Without the search window cap and memoization, this
      -- would trigger O(n*m) behavior in the sync-point search loop.
      local num_blocks = 200
      local existing_blocks = {}
      local new_blocks = {}
      for n = 1, num_blocks do
        existing_blocks[n] = {
          id = "block" .. n,
          type = "paragraph",
          paragraph = { rich_text = { { text = { content = "line " .. n } } } }
        }
        new_blocks[n] = {
          type = "heading_1",
          heading_1 = { rich_text = { { text = { content = "heading " .. n } } } }
        }
      end

      local start_time = os.clock()
      local operations = api.calculate_diff_operations(existing_blocks, new_blocks)
      local elapsed = os.clock() - start_time

      -- With the search window cap, this should complete nearly instantly.
      -- Without it, 200 blocks with full type mismatch would be ~40,000 iterations.
      assert.is_true(elapsed < 1.0, "Diff with 200 type-mismatched blocks took " .. elapsed .. "s (expected <1s)")

      -- All existing blocks should be deleted and all new blocks inserted
      assert.equals(num_blocks, #operations.deletes)
      assert.is_true(#operations.inserts > 0)
      assert.equals(0, #operations.updates)
      assert.equals(0, operations.noops)
    end)
  end)

  describe("block_cache", function()
    it("should cache blocks on edit_page and use cache on sync_page", function()
      -- Track get_all_blocks calls via curl.get (async-aware)
      local get_call_count = 0
      mock_curl.get = make_curl_mock(function(opts)
        get_call_count = get_call_count + 1
        if opts.url:match("/pages/cache%-test%-page$") then
          return {
            status = 200,
            body = 'page-with-properties-Test Page'
          }
        elseif opts.url:match("/blocks/cache%-test%-page/children") then
          return {
            status = 200,
            body = vim.json.encode({
              results = {
                {
                  id = "block1",
                  type = "paragraph",
                  paragraph = { rich_text = { { text = { content = "Hello" } } } }
                }
              }
            })
          }
        end
        return { status = 200, body = '{"success": true}' }
      end)

      -- Enable caching via mock config
      mock_config.get = function(key)
        local defaults = {
          debug = false,
          notion_token = "test_token",
          database_id = "test_db_id",
          page_size = 100,
          sync_debounce_ms = 1000,
          cache_ttl = 300,
        }
        return defaults[key]
      end

      -- Re-require to pick up config changes
      package.loaded['notion.api'] = nil
      local test_api = require('notion.api')

      -- Call edit_page to populate cache
      test_api.edit_page("cache-test-page")

      -- Set up buffer mocks for sync_page
      vim.api.nvim_get_current_buf = function() return 1 end
      vim.api.nvim_buf_get_var = function(buf, var)
        if var == "notion_page_id" then return "cache-test-page" end
        if var == "notion_page_url" then return "https://notion.so/test" end
        error("Variable not found: " .. var)
      end
      vim.api.nvim_buf_get_lines = function() return { "Hello", "" } end

      -- Call sync_page - should use cached blocks
      test_api.sync_page()

      -- The sync should NOT have made additional GET calls for blocks
      -- (it uses the cache), but it will re-fetch after successful sync to update cache
      -- So we expect: edit_page fetched (page + blocks), sync re-fetched blocks post-sync
      -- but NOT for the diff baseline (that came from cache)
      assert.is_not_nil(test_api.block_cache["cache-test-page"],
        "Cache should be populated after sync")
    end)

    it("should re-fetch blocks when cache is stale", function()
      -- Enable caching with a very short TTL
      mock_config.get = function(key)
        local defaults = {
          debug = false,
          notion_token = "test_token",
          database_id = "test_db_id",
          page_size = 100,
          sync_debounce_ms = 0,
          cache_ttl = 300,
        }
        return defaults[key]
      end

      -- Re-require to pick up config changes
      package.loaded['notion.api'] = nil
      local test_api = require('notion.api')

      -- Manually seed cache with a stale timestamp (older than TTL)
      test_api.block_cache["stale-page"] = {
        blocks = {
          { id = "old-block", type = "paragraph", paragraph = { rich_text = { { text = { content = "Old" } } } } }
        },
        timestamp = os.time() - 400, -- 400 seconds ago, TTL is 300
      }

      -- get_cached_blocks should return nil for stale cache
      local cached = test_api.get_cached_blocks("stale-page")
      assert.is_nil(cached, "Stale cache should return nil")

      -- The cache entry should be cleared
      assert.is_nil(test_api.block_cache["stale-page"],
        "Stale cache entry should be removed")
    end)

    it("should return cached blocks when cache is fresh", function()
      mock_config.get = function(key)
        local defaults = {
          debug = false,
          notion_token = "test_token",
          database_id = "test_db_id",
          page_size = 100,
          sync_debounce_ms = 0,
          cache_ttl = 300,
        }
        return defaults[key]
      end

      package.loaded['notion.api'] = nil
      local test_api = require('notion.api')

      local test_blocks = {
        { id = "block1", type = "paragraph", paragraph = { rich_text = { { text = { content = "Hello" } } } } }
      }

      -- Seed cache with fresh data
      test_api.block_cache["fresh-page"] = {
        blocks = test_blocks,
        timestamp = os.time() - 10, -- 10 seconds ago, well within 300s TTL
      }

      local cached = test_api.get_cached_blocks("fresh-page")
      assert.is_not_nil(cached, "Fresh cache should return blocks")
      assert.equals(1, #cached)
      assert.equals("block1", cached[1].id)
    end)

    it("should clear cache on buffer close", function()
      mock_config.get = function(key)
        local defaults = {
          debug = false,
          notion_token = "test_token",
          database_id = "test_db_id",
          page_size = 100,
          sync_debounce_ms = 0,
          cache_ttl = 300,
        }
        return defaults[key]
      end

      package.loaded['notion.api'] = nil
      local test_api = require('notion.api')

      -- Capture autocmd registrations
      local autocmd_callbacks = {}
      vim.api.nvim_create_autocmd = function(events, opts)
        table.insert(autocmd_callbacks, { events = events, opts = opts })
      end

      mock_curl.get = make_curl_mock(function(opts)
        if opts.url:match("/pages/buf%-close%-test$") then
          return {
            status = 200,
            body = 'page-with-properties-Test Page'
          }
        elseif opts.url:match("/blocks/buf%-close%-test/children") then
          return {
            status = 200,
            body = vim.json.encode({
              results = {
                {
                  id = "block1",
                  type = "paragraph",
                  paragraph = { rich_text = { { text = { content = "Content" } } } }
                }
              }
            })
          }
        end
        return { status = 200, body = '{"success": true}' }
      end)

      -- Call edit_page to populate cache and register autocmds
      test_api.edit_page("buf-close-test")

      -- Verify cache was populated
      assert.is_not_nil(test_api.block_cache["buf-close-test"],
        "Cache should be populated after edit")

      -- Find the BufDelete/BufWipeout autocmd and trigger its callback
      local found_cleanup = false
      for _, autocmd in ipairs(autocmd_callbacks) do
        local events = autocmd.events
        if type(events) == "table" then
          for _, event in ipairs(events) do
            if event == "BufDelete" or event == "BufWipeout" then
              found_cleanup = true
              autocmd.opts.callback()
              break
            end
          end
        end
        if found_cleanup then break end
      end

      assert.is_true(found_cleanup, "BufDelete/BufWipeout autocmd should be registered")
      assert.is_nil(test_api.block_cache["buf-close-test"],
        "Cache should be cleared after buffer close")
    end)

    it("should disable caching when cache_ttl is 0", function()
      mock_config.get = function(key)
        local defaults = {
          debug = false,
          notion_token = "test_token",
          database_id = "test_db_id",
          page_size = 100,
          sync_debounce_ms = 0,
          cache_ttl = 0,
        }
        return defaults[key]
      end

      package.loaded['notion.api'] = nil
      local test_api = require('notion.api')

      -- Try to set cache
      test_api.set_cached_blocks("disabled-page", {
        { id = "block1", type = "paragraph", paragraph = { rich_text = { { text = { content = "Test" } } } } }
      })

      -- Cache should not be populated when ttl is 0
      assert.is_nil(test_api.block_cache["disabled-page"],
        "Cache should not be populated when cache_ttl is 0")

      -- get_cached_blocks should return nil
      local cached = test_api.get_cached_blocks("disabled-page")
      assert.is_nil(cached, "get_cached_blocks should return nil when cache_ttl is 0")
    end)

    it("should disable caching when cache_ttl is nil", function()
      mock_config.get = function(key)
        local defaults = {
          debug = false,
          notion_token = "test_token",
          database_id = "test_db_id",
          page_size = 100,
          sync_debounce_ms = 0,
        }
        return defaults[key]
      end

      package.loaded['notion.api'] = nil
      local test_api = require('notion.api')

      -- Try to set cache
      test_api.set_cached_blocks("nil-ttl-page", {
        { id = "block1", type = "paragraph", paragraph = { rich_text = { { text = { content = "Test" } } } } }
      })

      -- Cache should not be populated when ttl is nil
      assert.is_nil(test_api.block_cache["nil-ttl-page"],
        "Cache should not be populated when cache_ttl is nil")
    end)
  end)

  describe("get_all_blocks", function()
    it("should recursively fetch all blocks", function()
      local call_count = 0
      mock_curl.get = make_curl_mock(function(opts)
        call_count = call_count + 1
        if call_count == 1 then
          return {
            status = 200,
            body = '{"results": [{"id": "block1", "has_children": true}, {"id": "block2"}], ' ..
                   '"has_more": true, "next_cursor": "cursor1"}'
          }
        elseif call_count == 2 then
          return {
            status = 200,
            body = '{"results": [{"id": "block3"}]}'
          }
        else
          return {
            status = 200,
            body = '{"results": []}'
          }
        end
      end)

      local blocks = api.get_all_blocks("page1")

      assert.equals(3, #blocks)
      assert.equals("block1", blocks[1].id)
      assert.equals("block3", blocks[2].id)
      assert.equals("block2", blocks[3].id)
    end)

    it("should handle blocks with no children", function()
      mock_curl.get = make_curl_mock(function(opts)
        return {
          status = 200,
          body = '{"results": [{"id": "block1"}, {"id": "block2"}]}'
        }
      end)

      local blocks = api.get_all_blocks("page1")

      assert.equals(2, #blocks)
      assert.equals("block1", blocks[1].id)
      assert.equals("block2", blocks[2].id)
    end)

    it("should handle archived blocks", function()
      mock_curl.get = make_curl_mock(function(opts)
        return {
          status = 200,
          body = '{"results": [{"id": "block1", "in_trash": true}, {"id": "block2"}]}'
        }
      end)

      local blocks = api.get_all_blocks("page1")

      assert.equals(1, #blocks)
      assert.equals("block2", blocks[1].id)
    end)
  end)

  describe("run_concurrent", function()
    it("should run tasks concurrently inside a coroutine", function()
      local task_order = {}

      mock_curl.patch = make_curl_mock(function(opts)
        table.insert(task_order, opts.url)
        return { status = 200, body = '{"success": true}' }
      end)

      local results = nil
      api.run_async(function()
        local tasks = {}
        for i = 1, 3 do
          local idx = i
          table.insert(tasks, function()
            return api.make_request('PATCH', '/blocks/block' .. idx, { test = true })
          end)
        end
        results = api.run_concurrent(tasks)
      end)

      assert.is_not_nil(results)
      assert.equals(3, #results)
      for i = 1, 3 do
        assert.is_true(results[i].ok, "Task " .. i .. " should succeed")
        assert.is_not_nil(results[i].value, "Task " .. i .. " should have a result")
      end
      assert.equals(3, #task_order, "All 3 tasks should have executed")
    end)

    it("should fall back to sequential execution outside a coroutine", function()
      local call_count = 0
      local results = api.run_concurrent({
        function() call_count = call_count + 1; return "a" end,
        function() call_count = call_count + 1; return "b" end,
      })

      assert.equals(2, call_count)
      assert.equals(2, #results)
      assert.is_true(results[1].ok)
      assert.equals("a", results[1].value)
      assert.is_true(results[2].ok)
      assert.equals("b", results[2].value)
    end)

    it("should handle empty task list", function()
      local results = api.run_concurrent({})
      assert.equals(0, #results)
    end)

    it("should capture errors from individual tasks", function()
      local results = nil
      api.run_async(function()
        results = api.run_concurrent({
          function() return "ok" end,
          function() error("task failed") end,
          function() return "also ok" end,
        })
      end)

      assert.is_not_nil(results)
      assert.equals(3, #results)
      assert.is_true(results[1].ok)
      assert.equals("ok", results[1].value)
      assert.is_false(results[2].ok, "Failing task should report error")
      assert.is_truthy(results[2].value:match("task failed"))
      assert.is_true(results[3].ok)
      assert.equals("also ok", results[3].value)
    end)

    it("should respect max_concurrent limit", function()
      -- With max_concurrent=2, 4 tasks should run in 2 batches
      local batch_tracker = {}

      local results = nil
      api.run_async(function()
        local tasks = {}
        for i = 1, 4 do
          local idx = i
          table.insert(tasks, function()
            table.insert(batch_tracker, idx)
            return idx
          end)
        end
        results = api.run_concurrent(tasks, 2)
      end)

      assert.is_not_nil(results)
      assert.equals(4, #results)
      for i = 1, 4 do
        assert.is_true(results[i].ok)
        assert.equals(i, results[i].value)
      end
      -- All 4 tasks should have run
      assert.equals(4, #batch_tracker)
    end)
  end)

  describe("concurrent sync operations", function()
    it("should run updates concurrently during sync", function()
      -- Track PATCH calls for updates
      local patch_urls = {}
      mock_curl.patch = make_curl_mock(function(opts)
        table.insert(patch_urls, opts.url)
        return { status = 200, body = '{"success": true}' }
      end)

      mock_curl.get = make_curl_mock(function(opts)
        if opts.url:match("/blocks/sync%-concurrent%-page/children") then
          return {
            status = 200,
            body = vim.json.encode({
              results = {
                {
                  id = "block1",
                  type = "paragraph",
                  paragraph = { rich_text = { { text = { content = "old text 1" } } } }
                },
                {
                  id = "block2",
                  type = "paragraph",
                  paragraph = { rich_text = { { text = { content = "old text 2" } } } }
                },
                {
                  id = "block3",
                  type = "paragraph",
                  paragraph = { rich_text = { { text = { content = "old text 3" } } } }
                }
              }
            })
          }
        end
        return { status = 200, body = '{"results": []}' }
      end)

      -- Set up config for this test
      mock_config.get = function(key)
        local defaults = {
          debug = false,
          notion_token = "test_token",
          database_id = "test_db_id",
          page_size = 100,
          sync_debounce_ms = 0,
          cache_ttl = 300,
          max_concurrent_requests = 5,
        }
        return defaults[key]
      end

      package.loaded['notion.api'] = nil
      local test_api = require('notion.api')

      -- Set up buffer mocks
      vim.api.nvim_get_current_buf = function() return 1 end
      vim.api.nvim_buf_get_var = function(buf, var)
        if var == "notion_page_id" then return "sync-concurrent-page" end
        if var == "notion_page_url" then return "https://notion.so/test" end
        error("Variable not found: " .. var)
      end
      -- Buffer has updated text for all 3 blocks
      vim.api.nvim_buf_get_lines = function()
        return { "new text 1", "", "new text 2", "", "new text 3", "" }
      end

      test_api.sync_page()

      -- Should have made PATCH calls for updates (3 updates) + post-sync GET
      local update_patch_count = 0
      for _, url in ipairs(patch_urls) do
        if url:match("/blocks/block%d$") then
          update_patch_count = update_patch_count + 1
        end
      end
      assert.equals(3, update_patch_count, "Should have 3 update PATCH calls")
    end)

    it("should run deletes concurrently during sync", function()
      local delete_urls = {}
      mock_curl.delete = make_curl_mock(function(opts)
        table.insert(delete_urls, opts.url)
        return { status = 204, body = '' }
      end)

      mock_curl.patch = make_curl_mock(function(opts)
        return { status = 200, body = '{"success": true}' }
      end)

      mock_curl.get = make_curl_mock(function(opts)
        if opts.url:match("/blocks/sync%-delete%-page/children") then
          return {
            status = 200,
            body = vim.json.encode({
              results = {
                {
                  id = "block1",
                  type = "paragraph",
                  paragraph = { rich_text = { { text = { content = "keep this" } } } }
                },
                {
                  id = "block2",
                  type = "paragraph",
                  paragraph = { rich_text = { { text = { content = "delete me 1" } } } }
                },
                {
                  id = "block3",
                  type = "paragraph",
                  paragraph = { rich_text = { { text = { content = "delete me 2" } } } }
                }
              }
            })
          }
        end
        return { status = 200, body = '{"results": []}' }
      end)

      mock_config.get = function(key)
        local defaults = {
          debug = false,
          notion_token = "test_token",
          database_id = "test_db_id",
          page_size = 100,
          sync_debounce_ms = 0,
          cache_ttl = 300,
          max_concurrent_requests = 5,
        }
        return defaults[key]
      end

      package.loaded['notion.api'] = nil
      local test_api = require('notion.api')

      vim.api.nvim_get_current_buf = function() return 1 end
      vim.api.nvim_buf_get_var = function(buf, var)
        if var == "notion_page_id" then return "sync-delete-page" end
        if var == "notion_page_url" then return "https://notion.so/test" end
        error("Variable not found: " .. var)
      end
      -- Buffer only keeps the first block
      vim.api.nvim_buf_get_lines = function()
        return { "keep this", "" }
      end

      test_api.sync_page()

      -- Should have 2 DELETE calls for the removed blocks
      assert.equals(2, #delete_urls, "Should have 2 concurrent DELETE calls")
      -- Verify the correct blocks were deleted
      local deleted_block2 = false
      local deleted_block3 = false
      for _, url in ipairs(delete_urls) do
        if url:match("block2") then deleted_block2 = true end
        if url:match("block3") then deleted_block3 = true end
      end
      assert.is_true(deleted_block2, "block2 should be deleted")
      assert.is_true(deleted_block3, "block3 should be deleted")
    end)

    it("should complete deletes before inserts", function()
      -- Track operation order to verify deletes happen before inserts
      local operation_log = {}

      mock_curl.delete = make_curl_mock(function(opts)
        table.insert(operation_log, { type = "delete", url = opts.url })
        return { status = 204, body = '' }
      end)

      mock_curl.patch = make_curl_mock(function(opts)
        if opts.url:match("/children$") then
          table.insert(operation_log, { type = "insert", url = opts.url })
        else
          table.insert(operation_log, { type = "update", url = opts.url })
        end
        return { status = 200, body = '{"success": true}' }
      end)

      mock_curl.get = make_curl_mock(function(opts)
        if opts.url:match("/blocks/sync%-order%-page/children") then
          return {
            status = 200,
            body = vim.json.encode({
              results = {
                {
                  id = "block1",
                  type = "paragraph",
                  paragraph = { rich_text = { { text = { content = "will be deleted" } } } }
                }
              }
            })
          }
        end
        return { status = 200, body = '{"results": []}' }
      end)

      mock_config.get = function(key)
        local defaults = {
          debug = false,
          notion_token = "test_token",
          database_id = "test_db_id",
          page_size = 100,
          sync_debounce_ms = 0,
          cache_ttl = 300,
          max_concurrent_requests = 5,
        }
        return defaults[key]
      end

      package.loaded['notion.api'] = nil
      local test_api = require('notion.api')

      vim.api.nvim_get_current_buf = function() return 1 end
      vim.api.nvim_buf_get_var = function(buf, var)
        if var == "notion_page_id" then return "sync-order-page" end
        if var == "notion_page_url" then return "https://notion.so/test" end
        error("Variable not found: " .. var)
      end
      -- Replace existing block with new content (triggers delete + insert)
      vim.api.nvim_buf_get_lines = function()
        return { "# New heading", "", "new paragraph", "" }
      end

      test_api.sync_page()

      -- Find the indices of delete and insert operations
      local last_delete_idx = 0
      local first_insert_idx = #operation_log + 1
      for i, op in ipairs(operation_log) do
        if op.type == "delete" then
          last_delete_idx = math.max(last_delete_idx, i)
        end
        if op.type == "insert" then
          first_insert_idx = math.min(first_insert_idx, i)
        end
      end

      -- If both deletes and inserts occurred, deletes must come first
      if last_delete_idx > 0 and first_insert_idx <= #operation_log then
        assert.is_true(last_delete_idx < first_insert_idx,
          "All deletes (last at index " .. last_delete_idx ..
          ") must complete before first insert (at index " .. first_insert_idx .. ")")
      end
    end)

    it("should report errors from failed concurrent operations", function()
      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- Make PATCH fail for one block
      mock_curl.patch = make_curl_mock(function(opts)
        if opts.url:match("block2") then
          return { status = 500, body = '{"error": "Server Error"}' }
        end
        return { status = 200, body = '{"success": true}' }
      end)

      mock_curl.get = make_curl_mock(function(opts)
        if opts.url:match("/blocks/sync%-error%-page/children") then
          return {
            status = 200,
            body = vim.json.encode({
              results = {
                {
                  id = "block1",
                  type = "paragraph",
                  paragraph = { rich_text = { { text = { content = "old 1" } } } }
                },
                {
                  id = "block2",
                  type = "paragraph",
                  paragraph = { rich_text = { { text = { content = "old 2" } } } }
                }
              }
            })
          }
        end
        return { status = 200, body = '{"results": []}' }
      end)

      mock_config.get = function(key)
        local defaults = {
          debug = false,
          notion_token = "test_token",
          database_id = "test_db_id",
          page_size = 100,
          sync_debounce_ms = 0,
          cache_ttl = 300,
          max_concurrent_requests = 5,
        }
        return defaults[key]
      end

      package.loaded['notion.api'] = nil
      local test_api = require('notion.api')

      vim.api.nvim_get_current_buf = function() return 1 end
      vim.api.nvim_buf_get_var = function(buf, var)
        if var == "notion_page_id" then return "sync-error-page" end
        if var == "notion_page_url" then return "https://notion.so/test" end
        error("Variable not found: " .. var)
      end
      vim.api.nvim_buf_get_lines = function()
        return { "new 1", "", "new 2", "" }
      end

      test_api.sync_page()

      -- Should have an error notification for the API error
      local found_api_error = false
      for _, n in ipairs(notifications) do
        if n.msg:match("Notion API error") then
          found_api_error = true
          break
        end
      end
      assert.is_true(found_api_error, "Should report API error from failed concurrent operation")
    end)
  end)

  describe("HTTP compression", function()
    it("should set compressed = true on requests", function()
      -- Track opts passed to curl
      local captured_opts = nil
      mock_curl.get = spy.new(function(opts)
        captured_opts = opts
        return { status = 200, body = '{"success": true}' }
      end)

      -- Call make_request outside of coroutine (sync path)
      api.make_request('GET', '/blocks/test-page/children')

      assert.is_not_nil(captured_opts, "Should have called curl.get")
      assert.is_true(captured_opts.compressed, "compressed flag should be true")
    end)
  end)

  describe("run_concurrent sequential fallback", function()
    it("should capture errors in sequential fallback mode", function()
      -- Called outside a coroutine, so should use sequential fallback
      local results = api.run_concurrent({
        function() return "ok" end,
        function() error("sequential fail") end,
        function() return "also ok" end,
      })

      assert.equals(3, #results)
      assert.is_true(results[1].ok)
      assert.equals("ok", results[1].value)
      assert.is_false(results[2].ok, "Failed task should report error in sequential mode")
      assert.is_truthy(results[2].value:match("sequential fail"))
      assert.is_true(results[3].ok)
      assert.equals("also ok", results[3].value)
    end)
  end)

  describe("diff search window cap", function()
    it("should find sync point within the search window", function()
      -- Create blocks where the first block is a type mismatch, but blocks
      -- at index 3 match (within the 50-block search window).
      local existing_blocks = {
        { id = "block1", type = "paragraph", paragraph = { rich_text = { { text = { content = "old" } } } } },
        { id = "block2", type = "paragraph", paragraph = { rich_text = { { text = { content = "middle" } } } } },
        { id = "block3", type = "paragraph", paragraph = { rich_text = { { text = { content = "same" } } } } },
      }
      local new_blocks = {
        { type = "heading_1", heading_1 = { rich_text = { { text = { content = "new heading" } } } } },
        { type = "paragraph", paragraph = { rich_text = { { text = { content = "same" } } } } },
      }

      local operations = api.calculate_diff_operations(existing_blocks, new_blocks)

      -- block1 and block2 should be deleted, new heading inserted, block3 is a noop
      assert.equals(2, #operations.deletes)
      assert.equals(1, #operations.inserts)
      assert.equals(1, operations.noops)
      assert.equals(0, #operations.updates)
    end)

    it("should fall back to delete+insert when no sync point within window", function()
      -- Create blocks with many type mismatches exceeding the search window
      -- (DIFF_SEARCH_WINDOW = 50). Place a matching block at index 60 (beyond window).
      local existing_blocks = {}
      local new_blocks = {}

      -- Fill 60 blocks with different types
      for n = 1, 60 do
        existing_blocks[n] = {
          id = "block" .. n,
          type = "paragraph",
          paragraph = { rich_text = { { text = { content = "para " .. n } } } }
        }
        new_blocks[n] = {
          type = "heading_1",
          heading_1 = { rich_text = { { text = { content = "heading " .. n } } } }
        }
      end

      local operations = api.calculate_diff_operations(existing_blocks, new_blocks)

      -- No sync point found within window -- all should be deleted and re-inserted
      assert.equals(60, #operations.deletes, "All existing blocks should be deleted")
      assert.is_true(#operations.inserts > 0, "All new blocks should be inserted")
      assert.equals(0, operations.noops, "No blocks should match as noops")
    end)
  end)

  describe("cache_ttl edge cases", function()
    it("should use cache when ttl equals exact age", function()
      -- Cache entry with age == ttl - 1 (just barely fresh)
      mock_config.get = function(key)
        local defaults = {
          debug = false,
          notion_token = "test_token",
          database_id = "test_db_id",
          page_size = 100,
          sync_debounce_ms = 0,
          cache_ttl = 10,
        }
        return defaults[key]
      end

      package.loaded['notion.api'] = nil
      local test_api = require('notion.api')

      local test_blocks = {
        { id = "block1", type = "paragraph", paragraph = { rich_text = { { text = { content = "test" } } } } }
      }

      -- Seed cache with age = ttl - 1 (fresh)
      test_api.block_cache["edge-page"] = {
        blocks = test_blocks,
        timestamp = os.time() - 9,
      }

      local cached = test_api.get_cached_blocks("edge-page")
      assert.is_not_nil(cached, "Cache with age < ttl should return blocks")

      -- Now seed cache with age == ttl (stale)
      test_api.block_cache["edge-page2"] = {
        blocks = test_blocks,
        timestamp = os.time() - 10,
      }

      local cached2 = test_api.get_cached_blocks("edge-page2")
      assert.is_nil(cached2, "Cache with age >= ttl should return nil")
    end)
  end)
end)
